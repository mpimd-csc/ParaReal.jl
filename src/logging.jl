struct Logger <: Logging.AbstractLogger
    events::RemoteChannel
end

Logging.min_enabled_level(::Logger) = Logging.BelowMinLevel
Logging.shouldlog(::Logger, lvl, mod, group, id) = group == :eventlog
Logging.catch_exceptions(::Logger) = false

function Logging.handle_message(l::Logger, lvl, msg, mod, group, id, file, line; kwargs...)
    put!(l.events, (; kwargs..., name=msg))
end

struct InMemoryLog
    status::Vector{Symbol}
    events::RemoteChannel
    eventlog::Vector{NamedTuple}
    handler::Task

    InMemoryLog(N::Int) = InMemoryLog(identity, N)

    function InMemoryLog(f, N::Int)
        status = [:Initialized for _ in 1:N]
        events = RemoteChannel(() -> Channel(2N))
        eventlog = NamedTuple[]
        handler = @async _eventhandler(f, $status, $events, $eventlog)
        new(status, events, eventlog, handler)
    end
end

"""
    getlogger(l, n)

Get the `AbstractLogger` to be used for parareal stage `n`.
"""
function getlogger end

getlogger(l::InMemoryLog, _) = Logger(l.events)
getlogger(l::AbstractLogger, _) = l
getlogger(l::Vector{<:AbstractLogger}, n) = l[n]

function _eventhandler(f, status, events, eventlog)
    while true
        msg = take!(events)
        @unpack n, name = msg
        # Process incoming event:
        e = f(msg)
        push!(eventlog, e)
        status[n] = name
        # Stop if no further events are to be expected:
        isdone(name) && all(isdone, status) && break
    end
    # Signal that events won't be processed anymore.
    # Sending further events will cause an error.
    close(events)
    nothing
end
