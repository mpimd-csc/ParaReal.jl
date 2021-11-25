abstract type Problem end

struct WrappedProblem <: Problem
    p
end

problem(p) = WrappedProblem(p)

unwrap(p::WrappedProblem) = p.p
unwrap(p) = p

abstract type Algorithm end

struct FunctionalAlgorithm <: Algorithm
    coarse
    fine
end

algorithm(csolve, fsolve) = FunctionalAlgorithm(csolve, fsolve)

struct Message
    cancelled::Bool
    converged::Bool
    u::Any
end

const MessageChannel = RemoteChannel{Channel{Message}}

Base.@kwdef struct StageConfig
    n::Int # corresponding step in the pipeline
    N::Int # total number of steps in the pipeline
    prev::MessageChannel # where to get new `u0`-values from
    next::MessageChannel # where to put `u0`-values for the next pipeline step
    sol::Future # where to put the solution objects after convergence
    logger::AbstractLogger
end

"""
Local solution over a single time slice
"""
struct LocalSolution{S}
    n::Int # step in the pipeline
    k::Int # number of Newton iterations
    sol::S
    retcode::Symbol
end

"""
Global solution over the whole time span
"""
struct GlobalSolution
    sols::Vector{Future}
    retcodes::Vector{Symbol}
    retcode::Symbol

    function GlobalSolution(sols)
        fetch_from_owner(f, rr) = remotecall_fetch(f∘fetch, rr.where, rr)
        retcodes = map(sols) do rsol
            isready(rsol) || return :Unknown
            fetch_from_owner(sol -> sol.retcode, rsol)
        end
        retcode = all(==(:Success), retcodes) ? :Success : :MaxIters
        new(sols, retcodes, retcode)
    end
end

"""
# Pipeline Interface

* [`init`](@ref)
* [`solve!`](@ref)
* [`cancel_pipeline!`](@ref)
"""
Base.@kwdef mutable struct Pipeline
    prob
    alg
    kwargs
    conns::Vector{MessageChannel}
    sol::Union{GlobalSolution, Nothing} = nothing

    # Worker stages:
    workers::Vector{Int}
    configs::Vector{StageConfig}
    sols::Vector{Future}
    tasks::Union{Vector{Task}, Nothing} = nothing

    # Status updates:
    cancelled::Bool = false
end

NextValue(u) = Message(false, false, u)
FinalValue(u) = Message(false, true, u)
Cancellation() = Message(true, false, nothing)

"""
    nextvalue(sol)

Extract the initial value for the next ParaReal iteration.
Defaults to `sol[end]`.
"""
nextvalue(sol) = sol[end]
nextvalue(m::Message) = m.u
