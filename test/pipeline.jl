using Distributed, Test

verbose = isinteractive()
verbose && @info "Verifying setup"
nprocs() < 3 && addprocs(3-nprocs())
ws = workers()[1:2]

using ParaReal, DifferentialEquations
@everywhere using ParaReal, DifferentialEquations

using ParaReal: init_pipeline,
                start_pipeline!,
                send_initial_value,
                cancel_pipeline!,
                wait_for_pipeline,
                collect_solutions,
                is_pipeline_started,
                is_pipeline_done,
                is_pipeline_cancelled,
                is_pipeline_failed

verbose && @info "Creating problem instance"
du = (u, _p, _t) -> u
u0 = [1.]
tspan = (0., 1.)
prob = ODEProblem(du, u0, tspan)

verbose && @info "Creating algorithm instance"
csolve = prob -> begin
    t0, tf = prob.tspan
    solve(prob, Euler(), dt=tf-t0)
end
fsolve = prob -> begin
    t0, tf = prob.tspan
    solve(prob, Euler(), dt=(tf-t0)/10)
end
alg = ParaReal.Algorithm(csolve, fsolve)

# Before attempting to run jobs on remote machines, perform a local smoke test
# to catch stupid mistakes early.

function wait4status(pl, i, states...)
    cb = () -> pl.status[i] in states
    timedwait(cb, 10.0)
end

function test_connections(ids)
    verbose && @info "Testing workers=$ids ..."
    verbose && @info "Initializing pipeline"
    global pl = init_pipeline(ids)
    @test !is_pipeline_started(pl)
    @test pl.status[1] == :Initialized

    verbose && @info "Starting worker tasks"
    start_pipeline!(pl, prob, alg, maxiters=10)
    @test is_pipeline_started(pl)
    @test !is_pipeline_done(pl)
    @test_throws Exception start_pipeline!(pl, prob, alg, maxiters=10)
    @test wait4status(pl, 1, :Started, :Waiting) == :ok

    verbose && @info "Sending initial value"
    send_initial_value(pl, prob)
    @test wait4status(pl, 1, :Running, :Done) == :ok

    verbose && @info "Collecting solutions"
    sol = collect_solutions(pl)
    @test is_pipeline_done(pl)
    @test !is_pipeline_failed(pl)
    @test pl.status == [:Done for _ in ids]

    # All spawned tasks should have finished by now.
    @test all(isready, pl.tasks)
    @test istaskdone(pl.eventhandler)
end

@testset "Smoke Test" begin
    test_connections([1,1,1,1])
end

# Assuming the stages of a pipeline are executed on different threads on each
# of the workers, we should explicitly test for pipeline configurations that
# send messages (between workers) from and to threads other than 1:

# process ids: 1 2
# thread ids:  1 1
one2one = ws

# process ids: 1 2 1 2
# thread ids:  1 1 2 2
m2n = repeat(ws, outer=2)

# process ids: 1 1 2 2
# thread ids:  1 2 1 2
n2one = repeat(ws, inner=2)

@testset "workers=$ids" for ids in (one2one, n2one, m2n)
    test_connections(ids)
end

delay = 5.0 # seconds
expensive(f) = x -> (sleep(delay); f(x))
expensive_alg = ParaReal.Algorithm(csolve, expensive(fsolve))

function test_cancellation(before::Bool, timeout)
    global pl = init_pipeline(one2one)
    start_pipeline!(pl, prob, expensive_alg, maxiters=10)
    before && send_initial_value(pl, prob)
    @test !is_pipeline_cancelled(pl)
    @test all(!=(:Cancelled), pl.status)

    cancel_pipeline!(pl)
    !before && send_initial_value(pl, prob)
    @test is_pipeline_cancelled(pl)

    t = @elapsed wait_for_pipeline(pl)
    @test t < timeout # pipeline did not complete; total runtime >= 2delay
    @test is_pipeline_done(pl)
    @test !is_pipeline_failed(pl)
    @test pl.status[end] == :Cancelled

    # All spawned tasks should have finished by now.
    @test all(isready, pl.tasks)
    @test istaskdone(pl.eventhandler)
end

@testset "Cancellation" begin
    @testset "Before sending initial value" begin
        verbose && @info "Testing cancellation before sending initial value"
        test_cancellation(false, 1.0)
    end
    @testset "After sending initial value" begin
        verbose && @info "Testing cancellation after sending initial value"
        test_cancellation(true, delay+1.0)
    end
end

function prepare(eventlog, stage)
    l = filter(e -> e.stage == stage, eventlog)
    sort!(l; by = e -> e.time_sent)
    map(e -> e.status, l)
end

@testset "Event Log" begin
    global pl = init_pipeline([1, 1])
    start_pipeline!(pl, prob, alg, maxiters=10)
    send_initial_value(pl, prob)
    wait_for_pipeline(pl)

    log = pl.eventlog
    s1 = prepare(log, 1)
    s2 = prepare(log, 2)
    @test s1 == [:Started, :Waiting, :Running, :Done]
    @test s2 == [:Started, :Waiting, :Running, :Running, :Done]
end
