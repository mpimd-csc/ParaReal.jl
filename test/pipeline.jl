using Distributed, Test

verbose = isinteractive()
verbose && @info "Verifying setup"
nprocs() < 3 && addprocs(3-nworkers())
ws = workers()[1:2]

using ParaReal, DifferentialEquations
@everywhere using ParaReal, DifferentialEquations

using ParaReal: init_pipeline,
                start_pipeline!,
                send_initial_value,
                collect_solutions,
                is_pipeline_started,
                is_pipeline_done,
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
alg = ParaRealAlgorithm(csolve, fsolve)

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
    pl = init_pipeline(ids)
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
