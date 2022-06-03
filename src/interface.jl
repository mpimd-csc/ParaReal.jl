# functions to extend for custom problem/solution types:

"""
    initial_value(prob)

Extract the initial value to kick off the ParaReal iterations.
"""
function initial_value end

"""
    remake_prob(prob::T, U₀, tspan) -> T

Create a new problem having the initial value `U₀` and time span `tspan`.
"""
function remake_prob end

"""
    value(sol)

Extract the (last) value from the solution object returned by `csolve` or `fsolve`
to be used within `update!`, cf. [`Algorithm`](@ref), or
to be used as the initial value for the next parareal stage, cf. [`remake_prob`](@ref).

Defaults to `sol[end]`.
"""
value(sol) = sol[end]

"""
    value(stage)

Extract the most recent parareal refinement as returned by e.g. [`default_update!`](@ref).
"""
value(s::Union{Stage,StageRef}) = s.Uᵏ⁻¹

"""
    dist(u, v)

Compute the distance between `u` and `v`.

Defaults to `LinearAlgebra.norm(u - v)`.
"""
dist(u, v) = norm(u - v)

"""
    solution(stage)

Extract the most recent fine solution as returned by `fsolve`.
"""
solution(s::Union{Stage,StageRef}) = s.Fᵏ⁻¹
