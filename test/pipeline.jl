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
    global l = ParaReal.InMemoryLog(length(ids))
    global pl = init(prob, alg; logger=l, workers=ids, maxiters=10, kwargs...)
    @test !is_pipeline_started(pl)
    @test !is_pipeline_done(pl)
    @test l.status[1] == :Initialized

    verbose && @info "Starting worker tasks"
    sol = solve!(pl)
    @test is_pipeline_started(pl)
    @test is_pipeline_done(pl)
    @test !is_pipeline_failed(pl)
    @test l.status == [:Done for _ in ids]

    # All spawned tasks should have finished by now.
    @test all(istaskdone, pl.tasks)

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

delay = 5.0 # seconds
expensive(f) = x -> (sleep(delay); f(x))
expensive_alg = ParaReal.algorithm(csolve_pl, expensive(fsolve_pl))

@testset "Cancellation before sending initial value" begin
    global l = ParaReal.InMemoryLog(length(one2one))
    global pl = init(prob, expensive_alg; logger=l, workers=one2one, maxiters=10, warmupc=false, warmupf=false)

    @test !is_pipeline_cancelled(pl)
    @test all(!=(:Cancelled), l.status)

    cancel_pipeline!(pl)
    solve!(pl)

    @test is_pipeline_cancelled(pl)
    @test is_pipeline_done(pl)
    @test !is_pipeline_failed(pl)
    @test l.status == [:Cancelled, :Cancelled]

    log = l.eventlog
    s1 = _prepare(log, 1)
    s2 = _prepare(log, 2)
    @test s1 == s2 == [:Started, :Waiting, :Cancelled]

    # All spawned tasks should have finished by now.
    @test all(istaskdone, pl.tasks)
end

@testset "Cancellation after sending initial value" begin
    global l = ParaReal.InMemoryLog(length(one2one))
    global pl = init(prob, expensive_alg; logger=l, workers=one2one, maxiters=10)

    @test !is_pipeline_cancelled(pl)
    @test all(!=(:Cancelled), l.status)

    bg = @async solve!(pl)
    while !is_pipeline_started(pl)
        sleep(0.1)
    end
    cancel_pipeline!(pl)
    wait(bg)

    @test is_pipeline_cancelled(pl)
    @test is_pipeline_done(pl)
    @test !is_pipeline_failed(pl)
    @test l.status == [:Cancelled, :Cancelled]

    # All spawned tasks should have finished by now.
    @test all(istaskdone, pl.tasks)
end

bang(_) = error("bang")
bangbang = ParaReal.algorithm(bang, bang) # Feuer frei!

@testset "Explosions" begin
    verbose && @info "Testing explosions"
    global l = ParaReal.InMemoryLog(2)
    global pl = init(prob, bangbang; logger=l, workers=[1, 1], maxiters=10, warmupc=false, warmupf=false)
    @test_throws CompositeException solve!(pl)
    @test is_pipeline_done(pl)
    @test is_pipeline_failed(pl)
    @test l.status == [:Failed, :Cancelled]
end

@testset "Explosions (with warm-up)" begin
    global l = ParaReal.InMemoryLog(2)
    global pl = init(prob, bangbang; logger=l, workers=[1, 1], maxiters=10)
    @test_throws CompositeException solve!(pl)
    @test l.status == [:Failed, :Failed]
end
