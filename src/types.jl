# This file is a part of ParaReal. License is MIT: https://spdx.org/licenses/MIT.html

"""
    Problem(p)

Simple wrapper that is only necessary to hook into `CommonSolve`.
"""
struct Problem
    p
end

"""
    Algorithm(csolve, fsolve[, update!])

* `csolve(prob) -> Gᵏ` computes the low-accurary / cheap / coarse solution
* `fsolve(prob) -> Fᵏ` computes the high-accurary / fine solution
* `update!(Uᵏ, value(Gᵏ), value(Fᵏ⁻¹), value(Gᵏ⁻¹)) -> Uᵏ`
  computes the Newton refinement and may work in-place.
  If not provided, this defaults to [`default_update!`](@ref).
  Solutions are unwrapped using [`value`](@ref).
"""
Base.@kwdef struct Algorithm
    csolve # csolve(prob) -> Gᵏ
    fsolve # fsolve(prob) -> Fᵏ
    update!::Any = default_update! # update!(Uᵏ, value(Gᵏ), value(Fᵏ⁻¹), value(Gᵏ⁻¹)) -> Uᵏ; may work in-place
end

Algorithm(csolve, fsolve) = Algorithm(; csolve, fsolve)

abstract type Schedule end
struct ProcessesSchedule <: Schedule
    workers::Vector{Int}
end
# TODO: Threads, Hybrid?, GPU?

ProcessesSchedule() = ProcessesSchedule(workers())

abstract type Message end
struct Cancellation <: Message end
struct Convergence <: Message end
struct NextValue <: Message
    U::Any
end

Message(msg::Message) = msg
Message(U) = NextValue(U)

const MessageChannel = RemoteChannel{Channel{Message}}

# constant; the same for all stages
struct Config
    alg::Algorithm
    N::Int # number of stages
    K::Int # maximum number of Newton refinements
    nconverged::Int # set to typemax(Int) to disable convergence checks, default: 3
    atol::Float64 # default: 0
    rtol::Float64 # default: size(U₀, 1) * eps()
    warmup::Tuple{Bool,Bool} # whether to warm up csolve and fsolve
end

# differs per stage; stores working state
Base.@kwdef mutable struct Stage
    prob # local problem
    loc # meaning depends on schedule
    prev::MessageChannel
    next::Union{Nothing,MessageChannel}
    n::Int
    k::Int = 0 # upcoming iteration, i.e. number of refinements computed is `k-1`
    cancelled::Bool = false
    converged::Bool = false
    nconverged::Int = 0 # number of refinements w/o significant change
    queue::Vector{Any} = Any[] # unprocessed U values of previous stage
    Fᵏ⁻¹ = nothing
    Gᵏ⁻¹ = nothing
    Uᵏ⁻¹ = nothing
    Uᵏ = nothing # work data, content might be garbage
    norm_Uᵏ⁻¹::Float64 = -1.0
    ex::Union{Nothing,Exception} = nothing
    st::Union{Nothing,Base.StackTrace} = nothing
end

# Holds a remote reference to a Stage to prevent data transfer to the managing process.
struct StageRef
    c::RemoteChannel{Channel{Stage}}

    StageRef(pid) = new(RemoteChannel(() -> Channel{Stage}(1), pid))
end

"""
    Pipeline{<:Schedule}

User interface:

* [`init`](@ref)
* [`solve!`](@ref)
* [`cancel_pipeline!`](@ref)
* [`is_pipeline_cancelled`](@ref)
* [`is_pipeline_failed`](@ref)
"""
Base.@kwdef mutable struct Pipeline{S}
    prob # global problem
    schedule::S
    config::Config
    stages::Vector{StageRef}
    conns::Vector{MessageChannel}
    cancelled::Bool = false
    logger = nothing
end
# The logger cannot be part of the stage, because it may not be possible to send
# it back to the manager, see e.g. LazyFileLogger.

"""
    Solution

Non-mutable container of relevant [`Pipeline`](@ref) information.
Its fields are:

* `retcode::Symbol`: return code
* `config::Config`: configuration that all pipeline stages have in common
* `stages::Vector{StageRef}`: references to the pipline stages
* `cancelled::Bool`: whether the pipeline has been cancelled, e.g. due to a stage failure
"""
struct Solution
    retcode::Symbol
    config::Config
    stages::Vector{StageRef}
    cancelled::Bool
end

function Solution(pl::Pipeline)
    retcode = any(s -> s.k > pl.config.K, pl.stages) ? :MaxIters : :Success
    Solution(
        retcode,
        pl.config,
        pl.stages,
        pl.cancelled,
    )
end
