# This file is a part of ParaReal. License is MIT: https://spdx.org/licenses/MIT.html

module ParaReal

# Pipeline interface:
import CommonSolve: solve, init, solve!
export solve, init, solve!
export cancel_pipeline!,
       is_pipeline_cancelled,
       is_pipeline_failed

# Schedules:
export ProcessesSchedule

import Base.Threads,
       Distributed

using Base.Iterators: countfrom, repeat
using Base.Threads: nthreads, @threads
using Distributed: Future,
                   RemoteChannel,
                   procs,
                   remotecall_fetch,
                   remotecall_wait,
                   workers,
                   @fetchfrom,
                   @spawnat
using LinearAlgebra: norm
using Logging
using LoggingExtras: FormatLogger, TransformerLogger
using UnPack: @unpack
using Requires

const T = Base.Threads
const D = Distributed

function __init__()
    @require DiffEqBase="2b5f629d-d688-5b77-993f-72d75c75574e" include("diffeq.jl")
end

include("types.jl")

include("interface.jl")

include("default_update.jl")
include("on_manager.jl")
include("on_worker.jl")

include("pipeline.jl")
include("status.jl")
include("logging.jl")

include("utils.jl")
include("util/stageref.jl")
include("show.jl")

end # module
