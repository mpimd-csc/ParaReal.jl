# This file is a part of ParaReal. License is MIT: https://spdx.org/licenses/MIT.html

using Distributed, Logging, Test

verbose = isinteractive()
verbose && @info "Verifying setup"
nprocs() == 1 && addprocs(1)

using ParaReal
@everywhere using ParaReal

verbose && @info "Defining new problem and solution types"
@everywhere begin
    # Define problem and solution types
    struct SomeProblem{T}
        X0::T
        tspan
    end
    struct SomeSolution{T}
        Xs::Vector{T}
    end

    # Implement interface
    ParaReal.initial_value(prob::SomeProblem) = prob.X0
    ParaReal.value(sol::SomeSolution) = last(sol.Xs)
    ParaReal.remake_prob(::SomeProblem, X0, tspan) = SomeProblem(X0, tspan)
end

verbose && @info "Creating problem instance"
X0 = [0]
tspan = (0., 1.)
prob = ParaReal.Problem(SomeProblem(X0, tspan))

verbose && @info "Solving SomeProblem"
somesolver = prob -> SomeSolution([map(x->x+1, prob.X0)])
alg = ParaReal.Algorithm(somesolver, somesolver)
ids = fill(first(workers()), 4)
schedule = ProcessesSchedule(ids)
sol = ParaReal.solve(prob, alg; schedule, logger=NullLogger())

@test sol isa ParaReal.Solution
@test sol.retcode == :Success

Xs = [ParaReal.value(s.Fᵏ⁻¹) for s in sol.stages]
@test Xs == [[1], [2], [3], [4]]
