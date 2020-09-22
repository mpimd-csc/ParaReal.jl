@everywhere using ParaReal

@everywhere begin
    # Define problem and solution types
    struct SomeProblem{T} X0::T; tspan; end
    struct SomeSolution{T} Xs::Vector{T} end

    # Implement interface
    ParaReal.initialvalue(prob::SomeProblem) = prob.X0
    ParaReal.nextvalue(sol::SomeSolution) = last(sol.Xs)
    ParaReal.remake(::SomeProblem; u0, tspan) = SomeProblem(u0, tspan)
end

# Optional Interface
function ParaReal.assemble_solution(prob::SomeProblem, alg, gsol)
    sols = gsol.sols
    init = empty(sols[1].Xs)
    Xs = mapreduce(sol -> sol.Xs, append!, sols, init=init)
    return SomeSolution(Xs)
end

# Create problem
X0 = [0]
tspan = (0., 1.)
prob = SomeProblem(X0, tspan)

# Solve
somesolver = prob -> SomeSolution([map(x->x+1, prob.X0)])
alg = ParaRealAlgorithm(somesolver, somesolver)
ids = fill(first(Distributed.workers()), 4)
sol = ParaReal.solve(prob, alg, workers=ids)

@test sol.Xs == [[1], [2], [3], [4]]
