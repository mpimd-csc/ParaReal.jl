struct ParaRealAlgorithm{CoarseAlgorithm,
                         FineAlgorithm,
                         UpdateFunction,
                        } <: DiffEqBase.DEAlgorithm
    coarse::CoarseAlgorithm
    fine::FineAlgorithm
    update!::UpdateFunction
end

ParaRealAlgorithm(coarse, fine) = ParaRealAlgorithm(coarse, fine, default_update!)

function default_update!(y_new, y_coarse, y_fine, y_coarse_old)
    @. y_new = y_coarse+y_fine-y_coarse_old
    nothing
end

const ValueChannel = RemoteChannel{Channel{Any}}
const RemoteTask = Future

Base.@kwdef struct StageConfig
    step::Int # corresponding step in the pipeline
    nsteps::Int # total number of steps in the pipeline
    prev::ValueChannel # where to get new `u0`-values from
    next::ValueChannel # where to put `u0`-values for the next pipeline step
    results::RemoteChannel # where to put the solution objects after convergence
end

Base.@kwdef mutable struct Pipeline
    conns::Vector{ValueChannel}
    results::ValueChannel

    workers::Vector{Int}
    configs::Vector{StageConfig}
    tasks::Union{Vector{RemoteTask}, Nothing} = nothing
end
