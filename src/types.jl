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
