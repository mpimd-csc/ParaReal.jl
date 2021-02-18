struct Algorithm{CoarseAlgorithm,
                         FineAlgorithm,
                         UpdateFunction,
                        } <: DiffEqBase.DEAlgorithm
    coarse::CoarseAlgorithm
    fine::FineAlgorithm
    update!::UpdateFunction
end

Algorithm(coarse, fine) = Algorithm(coarse, fine, default_update!)

function default_update!(y_new, y_coarse, y_fine, y_coarse_old)
    @. y_new = y_coarse+y_fine-y_coarse_old
    nothing
end

struct Message
    cancelled::Bool
    converged::Bool
    u::Any
end

const MessageChannel = RemoteChannel{Channel{Message}}

Base.@kwdef struct StageConfig
    step::Int # corresponding step in the pipeline
    nsteps::Int # total number of steps in the pipeline
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

iscancelled(c::RemoteChannel) = isready(c) && iscancelled(fetch(c))
iscancelled(m::Message) = m.cancelled
didconverge(m::Message) = m.converged
nextvalue(m::Message) = m.u
