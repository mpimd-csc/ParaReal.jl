function init_pipeline(workers::Vector{Int})
    conns = map(RemoteChannel, workers)
    nsteps = length(workers)
    results = RemoteChannel(() -> Channel(nsteps))
    configs = Vector{StageConfig}(undef, nsteps)

    # Initialize first stages:
    for i in 1:nsteps-1
        prev = conns[i]
        next = conns[i+1]
        configs[i] = StageConfig(step=i,
                                 nsteps=nsteps,
                                 prev=prev,
                                 next=next,
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
                                  results=results)

    Pipeline(conns=conns,
             results=results,
             workers=workers,
             configs=configs)
end

function start_pipeline!(pipeline::Pipeline, prob, alg; kwargs...)
    is_pipeline_started(pipeline) && error("Pipeline already started")
    @unpack workers, configs = pipeline
    tasks = map(workers, configs) do w, c
        D.@spawnat w execute_stage(prob, alg, c; kwargs...)
    end
    pipeline.tasks = tasks
    nothing
end

function send_initial_value(pipeline::Pipeline, prob)
    u0 = initialvalue(prob)
    c = first(pipeline.conns)
    put!(c, u0)
    close(c)
    nothing
end

"""
    is_pipeline_started(pl::Pipeline) -> Bool

Determine whether the stages of a pipeline have been started executing.
"""
is_pipeline_started(pl::Pipeline) = pl.tasks !== nothing

"""
    is_pipeline_done(pl::Pipeline) -> Bool

Determine whether all the stages of a pipeline have exited.
"""
is_pipeline_done(pl::Pipeline) = is_pipeline_started(pl) && all(isready, pl.tasks)

"""
    is_pipeline_failed(pl::Pipeline) -> Bool)

Determine whether some stage of a pipeline has exited because an exception was thrown.
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
