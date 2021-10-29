module ParaReal

import CommonSolve: solve

import Base.Threads,
       Distributed

using Base.Iterators: countfrom, repeat
using Base.Threads: nthreads, @threads
using Distributed: Future,
                   RemoteChannel,
                   procs,
                   remotecall_fetch,
                   workers,
                   @fetchfrom,
                   @spawnat
using LinearAlgebra: norm
using UnPack: @unpack
using Requires

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

function __init__()
    @require DiffEqBase="2b5f629d-d688-5b77-993f-72d75c75574e" include("diffeq.jl")
end

include("types.jl")
include("stages.jl")
include("pipeline.jl")
include("status.jl")

include("problem.jl")
include("solve.jl")

include("utils.jl")
include("show.jl")

end # module
