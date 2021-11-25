using ParaReal, Test
using LoggingExtras

struct TestProblem <: ParaReal.Problem tspan end
struct TestSolution end

ParaReal.remake_prob!(::TestProblem, _, _, tspan) = TestProblem(tspan)
ParaReal.initialvalue(::TestProblem) = [21]
ParaReal.nextvalue(::TestSolution) = [21]

prob = TestProblem((0., 42.))
stub = _ -> TestSolution()
alg = ParaReal.algorithm(stub, stub)

@testset "E.T. phone home" begin
    l = ParaReal.InMemoryLog(2)
    solve(prob, alg; logger=l, workers=[1, 1], warmupc=false, warmupf=false)
    @test istaskdone(l.handler)

    log = l.eventlog
    @test !isempty(log)

    s1 = _prepare(log, 1)
    s2 = _prepare(log, 2)
    @test length(s1) + length(s2) == length(log)

    @test s1 == [:Started,
                 :Waiting, :DoneWaiting,
                 :ComputingC, :DoneComputingC,
                 :ComputingU, :DoneComputingU,
                 :ComputingF, :DoneComputingF,
                 :StoringResults,
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
                 :StoringResults,
                 :Done]
end

@testset "Custom Loggers" begin
    l = ParaReal.InMemoryLog(2) do msg
        return (; msg..., time_received=time())
    end
    logger = TransformerLogger(ParaReal.Logger(l.events)) do args
        kwargs = (; args.kwargs..., time_sent=time())
        return (; args..., kwargs=kwargs)
    end

    solve(prob, alg; logger=logger, workers=[1, 1], warmupc=false, warmupf=false)
    @test istaskdone(l.handler)

    log = l.eventlog
    @test !isempty(log)
    @test all(e -> haskey(e, :time_sent), log)
    @test all(e -> haskey(e, :time_received), log)
end

@testset "JIT Warm-Up" begin
    @testset "warmupc=true" begin
        l = ParaReal.InMemoryLog(2)
        solve(prob, alg; logger=l, workers=[1, 1], warmupc=true, warmupf=false)

        s1 = _prepare(l.eventlog, 1)
        @test s1[1:4] == [:Started,
                          :WarmingUpC, :DoneWarmingUpC,
                          :Waiting]
    end
    @testset "warmupf=true" begin
        l = ParaReal.InMemoryLog(2)
        solve(prob, alg; logger=l, workers=[1, 1], warmupc=false, warmupf=true)

        s1 = _prepare(l.eventlog, 1)
        @test s1[1:4] == [:Started,
                          :WarmingUpF, :DoneWarmingUpF,
                          :Waiting]
    end
    @testset "warmupc=true, warmupf=true" begin
        l = ParaReal.InMemoryLog(2)
        solve(prob, alg; logger=l, workers=[1, 1], warmupc=true, warmupf=true)

        s1 = _prepare(l.eventlog, 1)
        @test s1[1:6] == [:Started,
                          :WarmingUpC, :DoneWarmingUpC,
                          :WarmingUpF, :DoneWarmingUpF,
                          :Waiting]
    end
end
