module ParaReal

import DiffEqBase

include("types.jl")
include("solution.jl")
include("problem.jl")

include("solve.jl")
include("worker.jl")

include("utils.jl")
include("compat.jl")

export ParaRealAlgorithm

end # module
