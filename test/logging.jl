using Distributed
using ParaReal, Test
using ParaReal: CommunicatingLogger, CommunicatingObserver
using ParaReal: LazyFormatLogger
using LoggingExtras
using LoggingFormats: LogFmt

prob = TestProblem((0., 42.))
stub = _ -> TestSolution()
alg = ParaReal.algorithm(stub, stub)

const TRACE1 = [
    :Started,
    :Waiting, :Waiting,
    :ComputingC, :ComputingC,
    :ComputingU, :ComputingU,
    :ComputingF, :ComputingF,
    :StoringResults,
    :Done,
]
const TRACE2 = [
    :Started,
    :Waiting, :Waiting,
    :ComputingC, :ComputingC,
    :ComputingU, :ComputingU,
    :ComputingF, :ComputingF,
    :Waiting, :Waiting,
    :ComputingC, :ComputingC,
    :ComputingU, :ComputingU,
    :ComputingF, :ComputingF,
    :StoringResults,
    :Done,
]

@testset "E.T. phone home" begin
    o = CommunicatingObserver(2)
    solve(prob, alg; logger=o, workers=[1, 1], warmupc=false, warmupf=false)
    @test istaskdone(o.handler)

    log = o.eventlog
    @test !isempty(log)

    s1 = _prepare(log, 1)
    s2 = _prepare(log, 2)
    @test length(s1) + length(s2) == length(log)

    @test s1 == TRACE1
    @test s2 == TRACE2
end

@testset "LazyFormatLogger" begin
    mktempdir() do dir
        logfile = joinpath(dir, "test.log")
        # first run
        l1 = LazyFormatLogger(LogFmt(), logfile)
        @test !isfile(logfile)
        with_logger(l1) do
            @info "Knock knock." _group=:eventlog
            @info "Who's there?" _group=:eventlog
        end
        @test isfile(logfile)
        @test countlines(logfile) == 2
        # second run; l1 must not be used again
        l2 = LazyFormatLogger(LogFmt(), logfile; append=true)
        with_logger(l2) do
            @info "Dejav." _group=:eventlog
            @info "Dejav who?" _group=:eventlog
        end
        lines = readlines(logfile)
        @test length(lines) == 4
        @test occursin("Knock knock.", lines[1])
        @test occursin("Who's there?", lines[2])
        @test occursin("Dejav.", lines[3])
        @test occursin("Dejav who?", lines[4])
        # third run; l1 and l2 must not be used again
        l3 = LazyFormatLogger(LogFmt(), logfile)
        with_logger(l3) do
            @info "Knock knock." _group=:eventlog
        end
        lines′ = readlines(logfile)
        @test length(lines′) == 1
        @test occursin("Knock knock.", lines′[1])
    end
end

function _extract(r, logfile)
    lines = readlines(logfile)
    map(lines) do l
        m = match(r, l)
        m == nothing && return :nothing
        Symbol(m[1])
    end
end

@testset "Multiple Custom Loggers" begin
    function _test_logger(workers, dir=mktempdir())
        logfiles = [joinpath(dir, "$n.log") for n in 1:2]
        loggers = [LazyFormatLogger(LogFmt(), file) for file in logfiles]
        solve(prob, alg; logger=loggers, workers=workers, warmupc=false, warmupf=false)
        @test readdir(dir) == ["1.log", "2.log"]
        @test countlines(logfiles[1]) == 11
        @test countlines(logfiles[2]) == 19
        tag = r" tag=\"([^\"]*)\""
        t1 = _extract(tag, logfiles[1])
        t2 = _extract(tag, logfiles[2])
        @test t1 == TRACE1
        @test t2 == TRACE2
    end
    @testset "local" begin
        _test_logger([1, 1])
    end
    @testset "remote" begin
        ws = addprocs(2)
        try
            @everywhere ws begin
                using LoggingFormats: LogFmt
                include("types.jl")
            end
            _test_logger(ws)
        finally
            rmprocs(ws)
        end
    end
end

@testset "Custom Loggers" begin
    o = CommunicatingObserver(2) do msg
        return (; msg..., time_received=time())
    end
    l = TransformerLogger(CommunicatingLogger(o.events)) do args
        kwargs = (; args.kwargs..., time_sent=time())
        return (; args..., kwargs=kwargs)
    end

    solve(prob, alg; logger=l, workers=[1, 1], warmupc=false, warmupf=false)
    @test istaskdone(o.handler)

    log = o.eventlog
    @test !isempty(log)
    @test all(e -> haskey(e, :time_sent), log)
    @test all(e -> haskey(e, :time_received), log)
end

@testset "JIT Warm-Up" begin
    @testset "warmupc=true" begin
        o = CommunicatingObserver(2)
        solve(prob, alg; logger=o, workers=[1, 1], warmupc=true, warmupf=false)

        s1 = _prepare(o.eventlog, 1)
        @test s1[1:4] == [:Started,
                          :WarmingUpC, :WarmingUpC,
                          :Waiting]
    end
    @testset "warmupf=true" begin
        o = CommunicatingObserver(2)
        solve(prob, alg; logger=o, workers=[1, 1], warmupc=false, warmupf=true)

        s1 = _prepare(o.eventlog, 1)
        @test s1[1:4] == [:Started,
                          :WarmingUpF, :WarmingUpF,
                          :Waiting]
    end
    @testset "warmupc=true, warmupf=true" begin
        o = CommunicatingObserver(2)
        solve(prob, alg; logger=o, workers=[1, 1], warmupc=true, warmupf=true)

        s1 = _prepare(o.eventlog, 1)
        @test s1[1:6] == [:Started,
                          :WarmingUpC, :WarmingUpC,
                          :WarmingUpF, :WarmingUpF,
                          :Waiting]
    end
end
