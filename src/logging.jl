struct Logger <: Logging.AbstractLogger
    events::RemoteChannel
end

Logging.min_enabled_level(::Logger) = Logging.BelowMinLevel
Logging.shouldlog(::Logger, lvl, mod, group, id) = group == :eventlog
Logging.catch_exceptions(::Logger) = false

function Logging.handle_message(l::Logger, lvl, msg, mod, group, id, file, line; kwargs...)
    t = time()
    put!(l.events, (; kwargs..., t=t, s=msg))
end

struct InMemoryLog
    status::Vector{Symbol}
    events::RemoteChannel
    eventlog::Vector{Event}
    handler::Task

    function InMemoryLog(N)
        status = [:Initialized for _ in 1:N]
        events = RemoteChannel(() -> Channel(2N))
        eventlog = Event[]
        handler = @async _eventhandler($status, $events, $eventlog)
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

function _eventhandler(status, events, eventlog)
    while true
        msg = take!(events)
        @unpack n, s, t = msg
        # Process incoming event:
        time_received = time()
        e = Event(n, s, t, time_received)
        push!(eventlog, e)
        status[n] = s
        # Stop if no further events are to be expected:
        isdone(s) && all(isdone, status) && break
    end
    # Signal that events won't be processed anymore.
    # Sending further events will cause an error.
    close(events)
    nothing
end
