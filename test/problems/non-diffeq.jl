using Distributed, Test

verbose = isinteractive()
verbose && @info "Verifying setup"
nprocs() == 1 && addprocs(1)

using ParaReal
@everywhere using ParaReal

verbose && @info "Defining new problem and solution types"
@everywhere begin
    # Define problem and solution types
    struct SomeProblem{T} <: ParaReal.Problem X0::T; tspan; end
    struct SomeSolution{T} Xs::Vector{T} end

    # Implement interface
    ParaReal.initialvalue(prob::SomeProblem) = prob.X0
    ParaReal.nextvalue(sol::SomeSolution) = last(sol.Xs)
    ParaReal.remake_prob!(::SomeProblem, _alg, u0, tspan) = SomeProblem(u0, tspan)
end

verbose && @info "Creating problem instance"
X0 = [0]
tspan = (0., 1.)
prob = SomeProblem(X0, tspan)

verbose && @info "Solving SomeProblem"
somesolver = prob -> SomeSolution([map(x->x+1, prob.X0)])
alg = ParaReal.algorithm(somesolver, somesolver)
ids = fill(first(workers()), 4)
sol = ParaReal.solve(prob, alg, workers=ids)

@test sol isa ParaReal.GlobalSolution
@test sol.retcode == :Success

sols = sol.sols
init = empty(sols[1].Xs)
Xs = mapreduce(sol -> sol.Xs, append!, sols, init=init)

@test Xs == [[1], [2], [3], [4]]
