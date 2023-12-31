# This file is a part of ParaReal. License is MIT: https://spdx.org/licenses/MIT.html

# Loggers

abstract type Logger <: AbstractLogger end

Logging.min_enabled_level(::Logger) = Logging.BelowMinLevel
Logging.shouldlog(::Logger, lvl, mod, group, id) = group == :eventlog
Logging.catch_exceptions(::Logger) = false

"""
    CommunicatingLogger(chan::RemoteChannel)

Logger sink that passes all logged key-value-pairs as well as the log message (under the `msg` key) to `chan`.
Use this logger via the [`CommunicatingObserver`](@ref) observer.
"""
struct CommunicatingLogger <: Logger
    events::RemoteChannel
end

function Logging.handle_message(l::CommunicatingLogger, lvl, msg, mod, group, id, file, line; kwargs...)
    put!(l.events, (; kwargs..., msg=msg))
end

"""
    LazyFormatLogger(f::Function, filename::String, append=false, always_flush=true)

Logger sink that formats the message and finally writes them to `filename`.
Opens file when handling the first log event.
Uses `LoggingExtras.FormatLogger` internally.

Handles only events having `_group=:eventlog`.

# Examples

```jldoctest
julia> using Logging

julia> using ParaReal: LazyFormatLogger

julia> fname = tempname();

julia> logger = LazyFormatLogger(fname) do io, args
           println(io, args.level, ": ", args.message)
       end;

julia> isfile(fname)
false

julia> with_logger(logger) do
           @info "Hello world!" _group=:eventlog
       end

julia> print(read(fname, String))
Info: Hello world!
```

# Reference

The logger does not test whether the file had already been opened.
Therefore, only one `LazyFormatLogger` for a particular file should exist.

Before first use, this logger is safe to be sent to other workers in a
`Distributed` environment. Once the `logger` field is initialized, it contains
an `IOStream` which is not safe to be sent over the network.
"""
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

# TODO: Do I need a finalizer to close the file handle?
# The logger will likely exist until Julia exits anyways.
function Logging.handle_message(l::LazyFormatLogger, args...; kwargs...)
    if l.logger === nothing
        fname = l.filename
        io = open(l.filename, l.append ? "a" : "w")
        l.logger = FormatLogger(l.f, io; always_flush=l.always_flush)
    end
    Logging.handle_message(l.logger, args...; kwargs...)
end

# Observers

"""
    CommunicatingObserver(N::Int) -> obs

Collect all log events of the parareal stages `n in 1:N` on the calling process.
Passes a [`CommunicatingLogger`](@ref) to every stage.
It's relevant fields are:

* `obs.status::Vector{Symbol}`: contains the last state information per stage
* `obs.eventlog::Vector{NamedTuple}`: contains all events in the order they were received
* `obs.handler::Task`: event handler task

!!! note
    The `CommunicatingObserver` is intended for testing and interactive use only.
    For practical computations, e.g. a non-interactive/headless context on a compute cluster,
    use e.g. a [`TimingFileObserver`](@ref) in order to retain as much information as possible in the case of a crash or deadlock.

# Reference

A too large value of `N::Int` will cause the last elements of `status` to remain `:Initialized`.
As a consequence, the internal event handler task will never terminate.
If the lifetime of your Julia program is limited, this may be a non-issue.

A too small value will cause the event handler to crash
(due to a `BoundsError` when setting `status[n]` for `n>N`),
which will very likely cause the pipeline to deadlock,
as the internal `RemoteChannel` buffers only `2N` messages.
"""
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
    TimingFileObserver(f::Function, t::Function, dir::String)

Create `dir` and have every parareal stage `n::Int` log to `dir/n.log`.
Add `time=t()` to every log event and format events using `f` via
[`LazyFormatLogger(f, ...)`](@ref LazyFormatLogger).

It is recommended to use a format, that is easily machine readable, e.g.

```julia
TimingFileObserver(LoggingFormats.LogFmt(), Base.time, "logfiles")
```
"""
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

getlogger(::Nothing, _) = nothing
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
