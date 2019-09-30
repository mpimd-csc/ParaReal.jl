using OrdinaryDiffEq

"""
doc
"""
struct ParaRealAlgorithm{CoarseAlgorithm,
                         FineAlgorithm,
                         UpdateFunction,
                        } <: OrdinaryDiffEqAlgorithm
    """
    * Will be called like `coarse(prob)`
    * Must return an integrator `integrator` that allows for `reinit!(integrator, u0)` and `solve!(integrator)`
    """
    coarse::CoarseAlgorithm
    "same as `coarse`"
    fine::FineAlgorithm
    "how to merge coarse and fine solutions"
    update!::UpdateFunction # to merge coarse and fine solutions
end

ParaRealAlgorithm(coarse, fine) = ParaRealAlgorithm(coarse, fine, default_update!)

#=
struct ParaRealCache <: OrdinaryDiffEqMutableCache
end

struct ParaRealConstantCache <: OrdinaryDiffEqConstantCache
end
=#

function default_update!(y_new, y_coarse, y_fine, y_coarse_old)
    @. y_new = y_coarse+y_fine-y_coarse_old
    nothing
end
