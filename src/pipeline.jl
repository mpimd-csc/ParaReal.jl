"""
    init(::ParaReal.Problem,
         ::ParaReal.Algorithm;
         kwargs...)

Initialize a pipeline to eventually run on the worker ids specified by
`workers`. Do not start the tasks executing the pipeline stages.
Supported keyword arguments:

* `workers = workers()`: worker ids to run the pipeline on
* `maxiters = 10`: maximum number of Newton refinements
* `tol = 1e-5`: relative error bound to judge about preliminary convergence
* `nconverged = 2`: lower bound on successive converged refinements
* `logger = NullLogger()`: where to log messages on the pipeline stages

Only if `nconverged` successive refinements show a relative change of
at most `tol`, the corresponding time slice is considered convergent.

Returns a [`Pipeline`](@ref).
"""
function init(prob::Problem, alg::Algorithm;
              workers::Vector{Int}=D.workers(),
              logger=NullLogger(),
              kwargs...)

    issubset(workers, D.procs()) ||
        error("Unknown worker ids in `$workers`, no subset of `$(D.procs())`")
    allunique(workers) ||
        @warn "Multiple tasks per worker won't run in parallel. Use for debugging only."

    bufsize = get(kwargs, :maxiters, 10) # TODO: find a better solution
    conns = map(workers) do w
        RemoteChannel(() -> Channel{Message}(bufsize), w)
    end
    N = length(workers)
    configs = Vector{StageConfig}(undef, N)
    sols = map(Future, workers)

    # Initialize first stages:
    for n in 1:N-1
        prev = conns[n]
        next = conns[n+1]
        sol = sols[n]
        configs[n] = StageConfig(n=n,
                                 N=N,
                                 prev=prev,
                                 next=next,
                                 sol=sol,
                                 logger=getlogger(logger, n))
    end

    # Initialize final stage:
    prev = next = conns[N]
    sol = sols[end]
    # Pass a `::ValueChannel` instead of `nothing` as to not trigger another
    # compilation. The value of `next` will never be accessed anyway.
    configs[N] = StageConfig(n=N,
                             N=N,
                             prev=prev,
                             next=next,
                             sol=sol,
                             logger=getlogger(logger, N))

    Pipeline(prob=unwrap(prob),
             alg=alg,
             kwargs=kwargs,
             conns=conns,
             workers=workers,
             configs=configs,
             sols=sols)
end

"""
    solve!(::ParaReal.Pipeline)

Create and schedule the tasks executing the pipeline stages.
Send the problem's initial value and wait for the completion of all stages.
Throws an error if the pipeline failed.
"""
function solve!(pipeline::Pipeline)
    pipeline.sol === nothing || return pipeline.sol
    is_pipeline_started(pipeline) && error("Pipeline already started")

    # Start pipeline executors and event handler:
    @unpack workers, configs = pipeline
    @unpack prob, alg, kwargs = pipeline
    pipeline.tasks = map(workers, configs) do w, c
        @async remotecall_wait(execute_stage, w, prob, alg, c; kwargs...)
    end

    # Send initial value:
    @unpack conns = pipeline
    c = first(conns)
    val = initialvalue(prob)
    put!(c, FinalValue(val))

    # Wait for completion; cancel on failure:
    @sync for (n, t) in enumerate(pipeline.tasks)
        @async try
            wait(t)
        catch e
            @warn "Cancelling pipeline due to failure on stage $n"
            cancel_pipeline!(pipeline)
            rethrow()
        end
    end

    @unpack sols = pipeline
    pipeline.sol = GlobalSolution(sols)
end

"""
    cancel_pipeline!(pl::Pipeline)

Abandon all computations along the pipeline.
Do not wait for all the stages to stop.

See [`Pipeline`](@ref) for the official interface.
"""
function cancel_pipeline!(pl::Pipeline)
    pl.cancelled && return
    pl.cancelled = true
    for c in pl.conns
        put!(c, Cancellation())
    end
end
