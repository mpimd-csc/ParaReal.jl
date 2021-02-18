module ParaReal

import Base.Threads,
       DiffEqBase,
       Distributed

using Base.Iterators: countfrom, repeat
using Base.Threads: nthreads, @threads
using Distributed: Future,
                   RemoteChannel,
                   procs,
                   remotecall,
                   workers,
                   @fetchfrom,
                   @spawnat
using LinearAlgebra: norm
using UnPack: @unpack

const T = Base.Threads
const D = Distributed

include("types.jl")
include("stages.jl")
include("pipeline.jl")

include("solution.jl")
include("problem.jl")
include("solve.jl")

include("utils.jl")

end # module
