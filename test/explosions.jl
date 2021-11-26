using ParaReal, Test

struct ExplodingProblem <: ParaReal.Problem tspan end
struct ExplodingSolution end

ParaReal.remake_prob!(::ExplodingProblem, _, _, tspan) = ExplodingProblem(tspan)
ParaReal.initialvalue(::ExplodingProblem) = [666.]
ParaReal.nextvalue(::ExplodingSolution) = [666.]

function ci_exit(e)
    get(ENV, "CI", "false") == "true" || return
    showerror(stderr, e, catch_backtrace())
    println(stderr)
    exit(1)
end

@testset "developer error" begin
    prob = ExplodingProblem((0., 666.))
    stub = _ -> ExplodingSolution()
    alg = ParaReal.algorithm(stub, stub)

    l = ParaReal.InMemoryLog(2)
    s = @async solve(prob, alg; logger=l, workers=[1, 1], warmupc=false, warmupf=false)
    try
        wait(l.handler)
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
