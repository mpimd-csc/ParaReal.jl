module ParaReal

import CommonSolve: solve

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

export solve
export init_pipeline,
       run_pipeline!,
       cancel_pipeline!,
       collect_solutions!
export is_pipeline_started,
       is_pipeline_done,
       is_pipeline_cancelled,
       is_pipeline_failed

include("types.jl")
include("stages.jl")
include("pipeline.jl")
include("status.jl")

include("problem.jl")
include("solve.jl")

include("utils.jl")
include("show.jl")

include("diffeq.jl")

end # module
