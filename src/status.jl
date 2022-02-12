isdone(s::Symbol) = s in (:Done, :Cancelled, :Failed)

isfailed(s::Stage) = s.ex !== nothing
isfailed(pl::Pipeline) = any(isfailed, pl.stages)

iscancelled(x::Union{Stage,Pipeline,Solution}) = x.cancelled
iscancelled(::Message) = false
iscancelled(::Cancellation) = true
iscancelled(c::MessageChannel) = isready(c) && iscancelled(fetch(c))

"""
    is_pipeline_cancelled(pl::Pipeline) -> Bool

Determine whether the pipeline had been cancelled.
"""
is_pipeline_cancelled(pl::Pipeline) = iscancelled(pl)

"""
    is_pipeline_failed(pl::Pipeline) -> Bool

Determine whether some stage of a pipeline has exited because an exception was thrown.
Does not block and not throw an error, if the pipeline failed.
"""
is_pipeline_failed(pl::Pipeline) = isfailed(pl)
