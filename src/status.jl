didconverge(m::Message) = m.converged

isdone(s::Symbol) = s in (:Done, :Cancelled, :Failed)

iscancelled(c::RemoteChannel) = isready(c) && iscancelled(fetch(c))
iscancelled(m::Message) = m.cancelled

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
is_pipeline_done(pl::Pipeline) = is_pipeline_started(pl) && all(istaskdone, pl.tasks)

"""
    is_pipeline_cancelled(pl::Pipeline) -> Bool

Determine whether the pipeline had been cancelled.
"""
is_pipeline_cancelled(pl::Pipeline) = pl.cancelled


"""
    is_pipeline_failed(pl::Pipeline) -> Bool

Determine whether some stage of a pipeline has exited because an exception was thrown.
Does not block and not throw an error, if the pipeline failed.
"""
function is_pipeline_failed(pl::Pipeline)
    is_pipeline_started(pl) || return false
    any(istaskfailed, pl.tasks)
end
