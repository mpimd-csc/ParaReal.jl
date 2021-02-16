"""
    init_pipeline(workers::Vector{Int})

Initialize a pipeline to eventually run on the worker ids specified by
`workers`. Do not start the tasks executing the pipeline stages.

See also:

* [`start_pipeline!`](@ref)
* [`send_initial_value`](@ref)
* [`wait_for_pipeline`](@ref)
* [`collect_solutions`](@ref)
* [`cancel_pipeline!`](@ref)
"""
function init_pipeline(workers::Vector{Int})
    conns = map(RemoteChannel, workers)
    nsteps = length(workers)
    results = RemoteChannel(() -> Channel(nsteps))
    ctx = CancelCtx()
    configs = Vector{StageConfig}(undef, nsteps)

    # Initialize first stages:
    for i in 1:nsteps-1
        prev = conns[i]
        next = conns[i+1]
        configs[i] = StageConfig(step=i,
                                 nsteps=nsteps,
                                 prev=prev,
                                 next=next,
                                 ctx=ctx,
                                 results=results)
    end

    # Initialize final stage:
    prev = next = conns[nsteps]
    # Pass a `::ValueChannel` instead of `nothing` as to not trigger another
    # compilation. The value of `next` will never be accessed anyway.
    configs[nsteps] = StageConfig(step=nsteps,
                                  nsteps=nsteps,
                                  prev=prev,
                                  next=next,
                                  ctx=ctx,
                                  results=results)

    Pipeline(conns=conns,
             results=results,
             ctx=ctx,
             workers=workers,
             configs=configs)
end

"""
    start_pipeline!(pipeline::Pipeline, prob, alg; kwargs...)

Create and schedule the tasks executing the pipeline stages.

See also:

* [`init_pipeline`](@ref)
* [`send_initial_value`](@ref)
* [`wait_for_pipeline`](@ref)
* [`collect_solutions`](@ref)
* [`cancel_pipeline!`](@ref)
"""
function start_pipeline!(pipeline::Pipeline, prob, alg; kwargs...)
    is_pipeline_started(pipeline) && error("Pipeline already started")
    @unpack workers, configs = pipeline
    tasks = map(workers, configs) do w, c
        D.@spawnat w execute_stage(prob, alg, c; kwargs...)
    end
    pipeline.tasks = tasks
    nothing
end

"""
    send_initial_value(pipeline::Pipeline, prob)

Kick off the ParaReal solver by sending the initial value of `prob`.
Do not wait until all computations are done.

See also:

* [`init_pipeline`](@ref)
* [`start_pipeline!`](@ref)
* [`wait_for_pipeline`](@ref)
* [`collect_solutions`](@ref)
* [`cancel_pipeline!`](@ref)
"""
function send_initial_value(pipeline::Pipeline, prob)
    u0 = initialvalue(prob)
    c = first(pipeline.conns)
    put!(c, u0)
    close(c)
    nothing
end

"""
    cancel_pipeline!(pl::Pipeline)

Abandon all computations along the pipeline.
Do not wait for all the stages to stop.

See also:

* [`init_pipeline`](@ref)
* [`start_pipeline!`](@ref)
* [`send_initial_value`](@ref)
* [`wait_for_pipeline`](@ref)
* [`collect_solutions`](@ref)
"""
cancel_pipeline!(pl::Pipeline) = cancel!(pl.ctx)

"""
    wait_for_pipeline(pl::Pipeline)

Wait for all the pipeline stages to finish.
Throws an error if the pipeline failed.

See also:

* [`init_pipeline`](@ref)
* [`start_pipeline!`](@ref)
* [`send_initial_value`](@ref)
* [`collect_solutions`](@ref)
* [`cancel_pipeline!`](@ref)
"""
function wait_for_pipeline(pl::Pipeline)
    errs = []
    for t in pl.tasks
        try
            wait(t)
        catch e
            push!(errs, e)
        end
    end
    isempty(errs) || throw(CompositeException(errs))
    nothing
end

### Status retrieval

"""
    is_pipeline_started(pl::Pipeline) -> Bool

Determine whether the stages of a pipeline have been started executing.
"""
is_pipeline_started(pl::Pipeline) = pl.tasks !== nothing

"""
    is_pipeline_done(pl::Pipeline) -> Bool

Determine whether all the stages of a pipeline have exited.
Does not block and not throw an error, if the pipeline failed.
"""
is_pipeline_done(pl::Pipeline) = is_pipeline_started(pl) && all(isready, pl.tasks)

"""
    is_pipeline_failed(pl::Pipeline) -> Bool

Determine whether some stage of a pipeline has exited because an exception was thrown.
Does not block and not throw an error, if the pipeline failed.
"""
function is_pipeline_failed(pl::Pipeline)
    is_pipeline_started(pl) || return false
    @unpack tasks = pl
    for t in tasks
        isready(t) || continue
        try
            # should return nothing:
            fetch(t)
        catch
            return true
        end
    end
    return false
end

"""
    is_pipeline_canceled(pl::Pipeline)

Determine whether the pipeline had been canceled.
"""
is_pipeline_canceled(pl::Pipeline) = iscanceled(pl.ctx)
