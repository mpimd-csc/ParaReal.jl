# Loggers

abstract type Logger <: AbstractLogger end

Logging.min_enabled_level(::Logger) = Logging.BelowMinLevel
Logging.shouldlog(::Logger, lvl, mod, group, id) = group == :eventlog
Logging.catch_exceptions(::Logger) = false

struct CommunicatingLogger <: Logger
    events::RemoteChannel
end

function Logging.handle_message(l::CommunicatingLogger, lvl, msg, mod, group, id, file, line; kwargs...)
    put!(l.events, (; kwargs..., msg=msg))
end

# Open file on first log, without testing whether the file had already been opened.
# Therefore, only one LazyFormatLogger for a particular file should exist.
#
# Before first use, this logger is safe to be sent to other workers in a
# Distributed environment. Once the `logger` field is initialized, it contains
# an `IOStream` which is not safe to be sent over the network.
mutable struct LazyFormatLogger <: Logger
    f::Function
    filename::String
    append::Bool
    always_flush::Bool
    logger::Union{Nothing,FormatLogger}
end

function LazyFormatLogger(f::Function, filename::String; append::Bool=false, always_flush::Bool=true)
    LazyFormatLogger(f, filename, append, always_flush, nothing)
end

function Logging.handle_message(l::LazyFormatLogger, args...; kwargs...)
    if l.logger === nothing
        fname = l.filename
        io = open(l.filename, l.append ? "a" : "w")
        l.logger = FormatLogger(l.f, io; always_flush=l.always_flush)
    end
    Logging.handle_message(l.logger, args...; kwargs...)
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

struct TimingFileObserver
    f::Function
    t::Function
    dir::String
    logger::Dict{Int,AbstractLogger}

    function TimingFileObserver(f::Function, t::Function, dir::String)
        mkpath(dir)
        new(f, t, dir, Dict{Int,AbstractLogger}())
    end
end

"""
    getlogger(l, n)

Get the `AbstractLogger` to be used for parareal stage `n`.
"""
function getlogger end

getlogger(o::CommunicatingObserver, _) = CommunicatingLogger(o.events)
getlogger(o::TimingFileObserver, n) = get!(o.logger, n) do
    file = joinpath(o.dir, "$n.log")
    TransformerLogger(LazyFormatLogger(o.f, file)) do args
        kwargs = (; args.kwargs..., time=o.t())
        return (; args..., kwargs=kwargs)
    end
end

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
