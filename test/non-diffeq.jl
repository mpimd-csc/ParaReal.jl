using ParaReal, Test

# Define problem and solution types
struct SomeProblem{T} X0::T; tspan; end
struct SomeSolution{T} Xs::Vector{T} end

# Implement interface
ParaReal.initialvalue(prob::SomeProblem) = prob.X0
ParaReal.nextvalue(sol::SomeSolution) = last(sol.Xs)
ParaReal.remake(::SomeProblem; u0, tspan) = SomeProblem(u0, tspan)
# optional:
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
sol = ParaReal.solve(prob, alg, ws=[1]) # use main process only

@test sol.Xs == [[i] for i in 1:length(sol.Xs)]
