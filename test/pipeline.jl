# This file is a part of ParaReal. License is MIT: https://spdx.org/licenses/MIT.html

using Distributed, Test
using Logging

verbose = isinteractive()
verbose && @info "Verifying setup"
nprocs() < 3 && addprocs(3-nprocs())
ws = workers()[1:2]

using ParaReal, OrdinaryDiffEq
using ParaReal: CommunicatingObserver
@everywhere using ParaReal, OrdinaryDiffEq

verbose && @info "Creating problem instance"
du = (u, _p, _t) -> u
u0 = [1.]
tspan = (0., 1.)
prob = ParaReal.Problem(ODEProblem(du, u0, tspan))

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
alg = ParaReal.Algorithm(csolve_pl, fsolve_pl)

# Before attempting to run jobs on remote machines, perform a local smoke test
# to catch stupid mistakes early.

function test_connections(ids, prob=prob, alg=alg)
    verbose && @info "Testing workers=$ids ..."
    verbose && @info "Initializing pipeline"
    global l = CommunicatingObserver(length(ids))
    s = ProcessesSchedule(ids)
    global pl = init(prob, alg; logger=l, schedule=s, maxiters=10)
    @test l.status[1] == :Initialized

    verbose && @info "Starting worker tasks"
    sol = solve!(pl)
    @test !is_pipeline_failed(pl)
    @test l.status == [:Done for _ in ids]

    # It is safe to retrieve solution twice:
    sol′ = solve!(pl)
    @test sol === sol′
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
expensive_alg = ParaReal.Algorithm(csolve_pl, expensive(fsolve_pl))

@testset "Cancellation before sending initial value" begin
    s = ProcessesSchedule(one2one)
    global l = CommunicatingObserver(length(one2one))
    global pl = init(prob, expensive_alg; logger=l, schedule=s, maxiters=10, warmupc=false, warmupf=false)

    @test !is_pipeline_cancelled(pl)
    @test all(!=(:Cancelled), l.status)

    cancel_pipeline!(pl)
    solve!(pl)

    @test is_pipeline_cancelled(pl)
    @test !is_pipeline_failed(pl)
    @test l.status == [:Cancelled, :Cancelled]

    log = l.eventlog
    s1 = _prepare(log, 1)
    s2 = _prepare(log, 2)
    @test s1 == s2 == [:Started, :WaitingRecv, :Cancelled]
end

@testset "Cancellation after sending initial value" begin
    s = ProcessesSchedule(one2one)
    global l = CommunicatingObserver(length(one2one))
    global pl = init(prob, expensive_alg; logger=l, schedule=s, maxiters=10)

    @test !is_pipeline_cancelled(pl)
    @test all(!=(:Cancelled), l.status)

    bg = @async solve!(pl)
    sleep(0.5) # brittle
    cancel_pipeline!(pl)
    wait(bg)

    @test is_pipeline_cancelled(pl)
    @test !is_pipeline_failed(pl)
    @test l.status == [:Cancelled, :Cancelled]
end

bang(_) = error("bang")
bangbang = ParaReal.Algorithm(bang, bang) # Feuer frei!

@testset "Explosions" begin
    verbose && @info "Testing explosions"
    s = ProcessesSchedule([1, 1])
    global l = CommunicatingObserver(2)
    global pl = init(prob, bangbang; logger=l, schedule=s, maxiters=10, warmupc=false, warmupf=false)
    @test_throws CompositeException solve!(pl)
    @test is_pipeline_failed(pl)
    @test l.status == [:Failed, :Cancelled]
end

@testset "Explosions (with warm-up)" begin
    s = ProcessesSchedule([1, 1])
    global l = CommunicatingObserver(2)
    global pl = init(prob, bangbang; logger=l, schedule=s, maxiters=10)
    @test_throws CompositeException solve!(pl)
    @test l.status == [:Failed, :Failed]
end

# Thanks to the authors of DeferredFutures.jl for this test strategy:
@testset "No local data" begin
    @everywhere ws include("types.jl")

    data_size = 80_000
    HUGE = _ -> rand(10_000)
    prob = ParaReal.Problem(TestProblem())
    alg = ParaReal.Algorithm(HUGE, HUGE)

    worker_size_before = asyncmap(ws) do w
        remotecall_fetch(w) do
            GC.gc()
            Base.summarysize(Distributed)
        end
    end
    GC.gc()
    size_before = Base.summarysize(Distributed)

    sol = solve(
        prob, alg;
        schedule=ProcessesSchedule(ws),
        rtol=0.0,
        logger=NullLogger(),
    )

    GC.gc()
    size_after = Base.summarysize(Distributed)
    worker_size_after = asyncmap(ws) do w
        remotecall_fetch(w) do
            GC.gc()
            Base.summarysize(Distributed)
        end
    end

    # The data must not reside on the local process:
    @test size_after < size_before + data_size

    # Each worker should have created at least one solution:
    @test worker_size_after[1] >= worker_size_before[1] + data_size
    @test worker_size_after[2] >= worker_size_before[2] + data_size
end
