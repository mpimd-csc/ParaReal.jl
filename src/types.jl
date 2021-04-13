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
    results::RemoteChannel # where to put the solution objects after convergence
    events::RemoteChannel # where to send status updates
end

struct Event
    stage::Int
    status::Symbol
    time_sent::Float64
    time_received::Float64
end

"""
Local solution over a single time slice
"""
struct LocalSolution{S}
    sol::S
    retcode::Symbol
end

"""
Global solution over the whole time span
"""
struct GlobalSolution{S}
    sols::Vector{S}
    retcodes::Vector{Symbol}
    retcode::Symbol

    function GlobalSolution(lsols::Vector{LocalSolution{S}}) where {S}
        sols = [s.sol for s in lsols]
        retcodes = [s.retcode for s in lsols]
        retcode = all(==(:Success), retcodes) ? :Success : :MaxIters
        new{S}(sols, retcodes, retcode)
    end
end

"""
# Pipeline Interface

* [`init_pipeline`](@ref)
* [`run_pipeline!`](@ref)
* [`cancel_pipeline!`](@ref)
* [`collect_solutions`](@ref)
"""
Base.@kwdef mutable struct Pipeline
    conns::Vector{MessageChannel}
    results::RemoteChannel

    # Worker stages:
    workers::Vector{Int}
    configs::Vector{StageConfig}
    tasks::Union{Vector{Future}, Nothing} = nothing

    # Status updates:
    status::Vector{Symbol}
    events::RemoteChannel
    eventlog::Vector{Event} = Event[]
    eventhandler::Union{Task, Nothing} = nothing
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
