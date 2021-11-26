# Loggers

struct CommunicatingLogger <: Logging.AbstractLogger
    events::RemoteChannel
end

Logging.min_enabled_level(::CommunicatingLogger) = Logging.BelowMinLevel
Logging.shouldlog(::CommunicatingLogger, lvl, mod, group, id) = group == :eventlog
Logging.catch_exceptions(::CommunicatingLogger) = false

function Logging.handle_message(l::CommunicatingLogger, lvl, msg, mod, group, id, file, line; kwargs...)
    put!(l.events, (; kwargs..., msg=msg))
end

# Observers

struct CommunicatingObserver
    status::Vector{Symbol}
    events::RemoteChannel
    eventlog::Vector{NamedTuple}
    handler::Task

    CommunicatingObserver(N::Int) = CommunicatingObserver(identity, N)

    function CommunicatingObserver(f, N::Int)
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

getlogger(o::CommunicatingObserver, _) = CommunicatingLogger(o.events)
getlogger(l::AbstractLogger, _) = l
getlogger(l::Vector{<:AbstractLogger}, n) = l[n]

function _eventhandler(f, status, events, eventlog)
    while true
        msg = take!(events)
        @unpack n, tag = msg
        # Process incoming event:
        e = f(msg)
        push!(eventlog, e)
        status[n] = tag
        # Stop if no further events are to be expected:
        isdone(tag) && all(isdone, status) && break
    end
    # Signal that events won't be processed anymore.
    # Sending further events will cause an error.
    close(events)
    nothing
end
