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
    N = length(workers)
    results = RemoteChannel(() -> Channel(N))
    configs = Vector{StageConfig}(undef, N)

    status = [:Initialized for _ in workers]
    events = RemoteChannel(() -> Channel(2N))

    # Initialize first stages:
    for n in 1:N-1
        prev = conns[n]
        next = conns[n+1]
        configs[n] = StageConfig(n=n,
                                 N=N,
                                 prev=prev,
                                 next=next,
                                 results=results,
                                 events=events)
    end

    # Initialize final stage:
    prev = next = conns[N]
    # Pass a `::ValueChannel` instead of `nothing` as to not trigger another
    # compilation. The value of `next` will never be accessed anyway.
    configs[N] = StageConfig(n=N,
                             N=N,
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
    try
        start_pipeline!(pipeline, prob, alg; kwargs...)
        send_initial_value(pipeline, prob)
        wait_for_pipeline(pipeline)
    catch e
        if e isa InterruptException
            @warn "Cancelling pipeline due to interrupt"
            cancel_pipeline!(pipeline)
        end
        rethrow()
    end
end

"""
    collect_solutions(pipeline::Pipeline)

Wait for the pipeline to finish and return a [`GlobalSolution`](@ref) of all
solutions for the smaller time slices (in order).

See [`Pipeline`](@ref) for the official interface.
"""
function collect_solutions(pipeline::Pipeline)
    # Check for errors:
    wait_for_pipeline(pipeline)

    @unpack results, workers = pipeline
    N = length(workers)

    # Collect local solutions. Sorting them shouldn't be necessary,
    # but as there is networking involved, we're rather safe than sorry:
    n, sol = take!(results)
    sols = Vector{typeof(sol)}(undef, N)
    sols[n] = sol
    for _ in 1:N-1
        n, sol = take!(results)
        sols[n] = sol
    end
    GlobalSolution(sols)
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
        n, s, t = take!(events)
        # Process incoming event:
        time_received = time()
        e = Event(n, s, t, time_received)
        push!(eventlog, e)
        status[n] = s
        # If stage failed, cancel whole pipeline:
        if isfailed(s)
            @warn "Cancelling pipeline due to failure on stage $n"
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
    n = config.n
    msg = (n, status, t)
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
