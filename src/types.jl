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

const ValueChannel = RemoteChannel{Channel{Any}}

Base.@kwdef struct StageConfig
    step::Int # corresponding step in the pipeline
    nsteps::Int # total number of steps in the pipeline
    prev::ValueChannel # where to get new `u0`-values from
    next::ValueChannel # where to put `u0`-values for the next pipeline step
    results::RemoteChannel # where to put the solution objects after convergence
    events::RemoteChannel # where to send status updates
    ctx::CancelCtx
end

struct Event
    stage::Int
    status::Symbol
    time_sent::Float64
    time_received::Float64
end

Base.@kwdef mutable struct Pipeline
    conns::Vector{ValueChannel}
    results::ValueChannel
    ctx::CancelCtx

    # Worker stages:
    workers::Vector{Int}
    configs::Vector{StageConfig}
    tasks::Union{Vector{Future}, Nothing} = nothing

    # Status updates:
    status::Vector{Symbol}
    events::RemoteChannel
    eventlog::Vector{Event} = Event[]
    eventhandler::Union{Task, Nothing} = nothing
end
