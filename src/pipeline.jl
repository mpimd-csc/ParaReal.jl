"""
    init_pipeline(workers::Vector{Int})

Initialize a pipeline to eventually run on the worker ids specified by
`workers`. Do not start the tasks executing the pipeline stages.

See [`Pipeline`](@ref) for the official interface.
"""
function init_pipeline(workers::Vector{Int})
    conns = map(workers) do w
        RemoteChannel(() -> Channel{Message}(1), w)
    end
    nsteps = length(workers)
    results = RemoteChannel(() -> Channel(nsteps))
    configs = Vector{StageConfig}(undef, nsteps)

    status = [:Initialized for _ in workers]
    events = RemoteChannel(() -> Channel(2nsteps))

    # Initialize first stages:
    for i in 1:nsteps-1
        prev = conns[i]
        next = conns[i+1]
        configs[i] = StageConfig(step=i,
                                 nsteps=nsteps,
                                 prev=prev,
                                 next=next,
                                 results=results,
                                 events=events)
    end

    # Initialize final stage:
    prev = next = conns[nsteps]
    # Pass a `::ValueChannel` instead of `nothing` as to not trigger another
    # compilation. The value of `next` will never be accessed anyway.
    configs[nsteps] = StageConfig(step=nsteps,
                                  nsteps=nsteps,
                                  prev=prev,
                                  next=next,
                                  results=results,
                                  events=events)

    Pipeline(conns=conns,
             results=results,
             workers=workers,
             configs=configs,
             events=events,
             status=status)
end

"""
    run_pipeline!(pipeline::Pipeline, prob, alg; kwargs...)

Create and schedule the tasks executing the pipeline stages.
Send the initial value of `prob` and wait for the completion of all stages.
Throws an error if the pipeline failed.

See [`Pipeline`](@ref) for the official interface.
"""
function run_pipeline!(pipeline::Pipeline, prob, alg; kwargs...)
    start_pipeline!(pipeline, prob, alg; kwargs...)
    send_initial_value(pipeline, prob)
    wait_for_pipeline(pipeline)
end

"""
    start_pipeline!(pipeline::Pipeline, prob, alg; kwargs...)

Create and schedule the tasks executing the pipeline stages.

Not part of the official [`Pipeline`](@ref) interface.
"""
function start_pipeline!(pipeline::Pipeline, prob, alg; kwargs...)
    is_pipeline_started(pipeline) && error("Pipeline already started")
    @unpack workers, configs = pipeline
    tasks = map(workers, configs) do w, c
        D.@spawnat w execute_stage(prob, alg, c; kwargs...)
    end
    pipeline.tasks = tasks
    pipeline.eventhandler = @async _eventhandler(pipeline)
    nothing
end

function _eventhandler(pipeline::Pipeline)
    @unpack status, events, eventlog = pipeline
    while true
        i, s, t = take!(events)
        # Process incoming event:
        time_received = time()
        e = Event(i, s, t, time_received)
        push!(eventlog, e)
        status[i] = s
        # If stage failed, cancel whole pipeline:
        if isfailed(s)
            @warn "Cancelling pipeline due to failure on stage $i"
            cancel_pipeline!(pipeline)
        end
        # Stop if no further events are to be expected:
        isdone(s) && all(isdone, status) && break
    end
    # Signal that events won't be processed anymore.
    # Sending further events will cause an error.
    close(events)
    nothing
end

function _send_status_update(config::StageConfig, status::Symbol)
    t = time()
    i = config.step
    msg = (i, status, t)
    put!(config.events, msg)
    nothing
end

"""
    send_initial_value(pipeline::Pipeline, prob)

Kick off the ParaReal solver by sending the initial value of `prob`.
Do not wait until all computations are done.

Not part of the official [`Pipeline`](@ref) interface.
"""
function send_initial_value(pipeline::Pipeline, prob)
    u0 = initialvalue(prob)
    c = first(pipeline.conns)
    put!(c, FinalValue(u0))
    nothing
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

"""
    wait_for_pipeline(pl::Pipeline)

Wait for all the pipeline stages to finish.
Throws an error if the pipeline failed.

Not part of the official [`Pipeline`](@ref) interface.
"""
function wait_for_pipeline(pl::Pipeline)
    errs = []
    # Wait for stage executors:
    for t in pl.tasks
        e = fetch(t)
        e isa Exception || continue
        push!(errs, e)
    end
    # Wait for event handler:
    try
        wait(pl.eventhandler)
    catch e
        push!(errs, e)
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
        e = fetch(t)
        e isa Exception && return true
    end
    return false
end

"""
    is_pipeline_cancelled(pl::Pipeline)

Determine whether the pipeline had been cancelled.
"""
is_pipeline_cancelled(pl::Pipeline) = pl.cancelled
