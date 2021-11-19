using Distributed, Test

verbose = isinteractive()
verbose && @info "Verifying setup"
nprocs() < 3 && addprocs(3-nprocs())
ws = workers()[1:2]

using ParaReal, OrdinaryDiffEq
@everywhere using ParaReal, OrdinaryDiffEq

verbose && @info "Creating problem instance"
du = (u, _p, _t) -> u
u0 = [1.]
tspan = (0., 1.)
prob = ParaReal.problem(ODEProblem(du, u0, tspan))

verbose && @info "Creating algorithm instance"
@everywhere begin
    csolve_pl(prob) = begin
        t0, tf = prob.tspan
        solve(prob, Euler(), dt=tf-t0)
    end
    fsolve_pl(prob) = begin
        t0, tf = prob.tspan
        solve(prob, Euler(), dt=(tf-t0)/10)
    end
end
alg = ParaReal.algorithm(csolve_pl, fsolve_pl)

# Before attempting to run jobs on remote machines, perform a local smoke test
# to catch stupid mistakes early.

function test_connections(ids, prob=prob, alg=alg; nolocaldata=true, kwargs...)
    verbose && @info "Testing workers=$ids ..."
    verbose && @info "Initializing pipeline"
    global pl = init(prob, alg; workers=ids, maxiters=10, kwargs...)
    @test !is_pipeline_started(pl)
    @test !is_pipeline_done(pl)
    @test pl.status[1] == :Initialized

    verbose && @info "Starting worker tasks"
    sol = solve!(pl)
    @test is_pipeline_started(pl)
    @test is_pipeline_done(pl)
    @test !is_pipeline_failed(pl)
    @test pl.status == [:Done for _ in ids]

    # All spawned tasks should have finished by now.
    @test all(istaskdone, pl.tasks)
    @test istaskdone(pl.eventhandler)

    # It is safe to retrieve solution twice:
    sol′ = solve!(pl)
    @test sol === sol′

    nolocaldata || return
    # Unless the computations have been performed on this process,
    # the references to the local solutions should not contain any data.
    @test all(f -> f.v === nothing, sol.sols)
end

@testset "Smoke Test" begin
    test_connections([1,1,1,1]; nolocaldata=false)
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

function prepare(eventlog, stage)
    l = filter(e -> e.stage == stage, eventlog)
    sort!(l; by = e -> e.time_sent)
    map(e -> e.status, l)
end

@testset "Event Log" begin
    global pl = init(prob, alg; workers=[1, 1], maxiters=10, warmupc=false, warmupf=false)
    solve!(pl)

    log = pl.eventlog
    s1 = prepare(log, 1)
    s2 = prepare(log, 2)
    @test s1 == [:Started,
                 :Waiting, :DoneWaiting,
                 :ComputingC, :DoneComputingC,
                 :ComputingU, :DoneComputingU,
                 :ComputingF, :DoneComputingF,
                 :Done]
    @test s2 == [:Started,
                 :Waiting, :DoneWaiting,
                 :ComputingC, :DoneComputingC,
                 :ComputingU, :DoneComputingU,
                 :ComputingF, :DoneComputingF,
                 :Waiting, :DoneWaiting,
                 :ComputingC, :DoneComputingC,
                 :ComputingU, :DoneComputingU,
                 :ComputingF, :DoneComputingF,
                 :Done]
end

@testset "Event Log (with warm up)" begin
    pl = init(prob, alg; workers=[1, 1], maxiters=10, warmupc=true, warmupf=false)
    solve!(pl)
    log = pl.eventlog
    s1 = prepare(log, 1)
    @test s1[1:4] == [:Started,
                      :WarmingUpC, :DoneWarmingUpC,
                      :Waiting]

    pl = init(prob, alg; workers=[1, 1], maxiters=10, warmupc=false, warmupf=true)
    solve!(pl)
    log = pl.eventlog
    s1 = prepare(log, 1)
    @test s1[1:4] == [:Started,
                      :WarmingUpF, :DoneWarmingUpF,
                      :Waiting]

    pl = init(prob, alg; workers=[1, 1], maxiters=10, warmupc=true, warmupf=true)
    solve!(pl)
    log = pl.eventlog
    s1 = prepare(log, 1)
    @test s1[1:6] == [:Started,
                      :WarmingUpC, :DoneWarmingUpC,
                      :WarmingUpF, :DoneWarmingUpF,
                      :Waiting]
end

delay = 5.0 # seconds
expensive(f) = x -> (sleep(delay); f(x))
expensive_alg = ParaReal.algorithm(csolve_pl, expensive(fsolve_pl))

@testset "Cancellation before sending initial value" begin
    global pl = init(prob, expensive_alg; workers=one2one, maxiters=10, warmupc=false, warmupf=false)

    @test !is_pipeline_cancelled(pl)
    @test all(!=(:Cancelled), pl.status)

    cancel_pipeline!(pl)
    solve!(pl)

    @test is_pipeline_cancelled(pl)
    @test is_pipeline_done(pl)
    @test !is_pipeline_failed(pl)
    @test pl.status == [:Cancelled, :Cancelled]

    log = pl.eventlog
    s1 = prepare(log, 1)
    s2 = prepare(log, 2)
    @test s1 == s2 == [:Started, :Waiting, :Cancelled]

    # All spawned tasks should have finished by now.
    @test all(istaskdone, pl.tasks)
    @test istaskdone(pl.eventhandler)
end

@testset "Cancellation after sending initial value" begin
    global pl = init(prob, expensive_alg; workers=one2one, maxiters=10)

    @test !is_pipeline_cancelled(pl)
    @test all(!=(:Cancelled), pl.status)

    bg = @async solve!(pl)
    while !is_pipeline_started(pl)
        sleep(0.1)
    end
    cancel_pipeline!(pl)
    wait(bg)

    @test is_pipeline_cancelled(pl)
    @test is_pipeline_done(pl)
    @test !is_pipeline_failed(pl)
    @test pl.status == [:Cancelled, :Cancelled]

    # All spawned tasks should have finished by now.
    @test all(istaskdone, pl.tasks)
    @test istaskdone(pl.eventhandler)
end

bang(_) = error("bang")
bangbang = ParaReal.algorithm(bang, bang) # Feuer frei!

@testset "Explosions" begin
    verbose && @info "Testing explosions"
    global pl = init(prob, bangbang; workers=[1, 1], maxiters=10, warmupc=false, warmupf=false)
    @test_throws CompositeException solve!(pl)
    @test is_pipeline_done(pl)
    @test is_pipeline_failed(pl)
    @test pl.status == [:Failed, :Cancelled]
end

@testset "Explosions (with warm-up)" begin
    global pl = init(prob, bangbang; workers=[1, 1], maxiters=10)
    @test_throws CompositeException solve!(pl)
    @test pl.status == [:Failed, :Failed]
end
