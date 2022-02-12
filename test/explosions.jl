using ParaReal, Test

struct ExplodingProblem tspan end
struct ExplodingSolution end

ParaReal.remake_prob(::ExplodingProblem, _, tspan) = ExplodingProblem(tspan)
ParaReal.initial_value(::ExplodingProblem) = [666.]
ParaReal.value(::ExplodingSolution) = Float64[]

function ci_exit(e)
    get(ENV, "CI", "false") == "true" || return
    showerror(stderr, e, catch_backtrace())
    println(stderr)
    exit(1)
end

@testset "developer error" begin
    prob = ParaReal.Problem(ExplodingProblem((0., 666.)))
    stub = _ -> ExplodingSolution()
    alg = ParaReal.Algorithm(stub, stub)

    o = ParaReal.CommunicatingObserver(2)
    s = @async solve(
        prob, alg;
        logger=o,
        schedule=ProcessesSchedule([1, 1]),
        warmupc=false,
        warmupf=false,
    )
    try
        wait(o.handler)
    catch e
        @error "Event handler failed"
        # If running in CI, fail hard to avoid a deadlock/timeout:
        ci_exit(e)
        rethrow()
    end

    try
        wait(s)
    catch e
        @error "Pipeline failed"
        # If running in CI, fail hard to avoid a deadlock/timeout:
        ci_exit(e)
        rethrow()
    end
end
