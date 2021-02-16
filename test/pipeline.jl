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
                is_pipeline_canceled,
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
    verbose && @info "Testing workers=$ids ..."
    verbose && @info "Initializing pipeline"
    global pl = init_pipeline(ids)
    @test !is_pipeline_started(pl)

    verbose && @info "Starting worker tasks"
    start_pipeline!(pl, prob, alg, maxiters=10)
    @test is_pipeline_started(pl)
    @test !is_pipeline_done(pl)
    @test_throws Exception start_pipeline!(pl, prob, alg, maxiters=10)

    verbose && @info "Sending initial value"
    send_initial_value(pl, prob)

    verbose && @info "Collecting solutions"
    sol = collect_solutions(pl)
    @test is_pipeline_done(pl)
    @test !is_pipeline_failed(pl)
end

delay = 5.0 # seconds
expensive(f) = x -> (sleep(delay); f(x))
expensive_alg = ParaReal.Algorithm(csolve, expensive(fsolve))

function test_cancellation(before::Bool, timeout)
    global pl = init_pipeline(one2one)
    start_pipeline!(pl, prob, expensive_alg, maxiters=10)
    before && send_initial_value(pl, prob)
    @test !is_pipeline_canceled(pl)

    cancel_pipeline!(pl)
    !before && send_initial_value(pl, prob)
    @test is_pipeline_canceled(pl)

    t = @elapsed wait_for_pipeline(pl)
    @test t < timeout # pipeline did not complete; total runtime >= 2delay
    @test is_pipeline_done(pl)
    @test !is_pipeline_failed(pl)
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
