# [Logging](@id logging_usage)

```@meta
CurrentModule=ParaReal
```

`ParaReal.jl` uses Julia's [Logging](https://docs.julialang.org/en/v1/stdlib/Logging/)
standard library to signal certain lifetime events of a parareal stage `n::Int`.
Each event is recorded in the `:eventlog` group, e.g.

```julia
@info "Stage started" tag=:Started n type=:singleton _group=:eventlog
```

## Types of events
### Framed events

For the following events, begin (`type=:start`) and end (`type=:stop`) are recorded:

| Tag | Log Level| Description | Payload |
|:---|:---:|:---|:---|
| WarmingUpC | debug | warm-up of coarse solver, cf. [`Algorithm`](@ref) ||
| WarmingUpF | debug | warm-up of fine solver, cf. [`Algorithm`](@ref) ||
| ComputingC | debug | execution of coarse solver | `k::Int` |
| ComputingF | debug | execution of fine solver | `k::Int` |
| ComputingU | debug | execution of parareal update function, cf. [`Algorithm`](@ref) | `k::Int` |
| CheckConv | debug | convergence check, cf. [`init`](@ref) | `k::Int` |
| WaitingRecv | debug | waiting for / receiving new data from the previous parareal stage `n-1` | `k::Int`[^1], `payload::Message` |
| WaitingSend | debug | sending data too the next parareal stage `n+1` | `k::Int`[^1] |

### Snap-shots

Furthermore, the following snap-shots (`type=:singleton`) are recorded:

| Tag | Log Level| Description | Payload |
|:---|:---:|:---|:---|
| Started | info | stage / its worker routing started ||
| Done | info | stage finished all computations | `k::Int`, `converged::Bool` |
| Failed | error | an uncaught exception occurred inside the stage logic ||
| Cancelled | warn | stage has been cancelled ||

A cancellation may be caused by the user, cf. [`cancel_pipeline!`](@ref),
or by a failure on a different stage.

[^1]:
    The counter `k::Int` associated to the sending/receiving of messages is
    currently not related to the number of parareal refinements `k::Int`
    associated to e.g. `:ComputingU`.

## Custom loggers and observers

Every parareal stage `n::Int` may use its own logger.
This logger handles all the events described above,
as well as all events logged by `csolve`, `fsolve`, and `update!` (cf. [`Algorithm`](@ref)) themselves.
It may be specified using the `logger` keyword of [`init`](@ref) (or `solve`),
which may be set to `nothing` (default), an instance of `AbstractLogger`, or some "observer".

An "observer" describes a more elaborate strategy of providing each parareal stage with its own logger.
The simplest observer is a `vec::Vector{<:AbstractLogger}`,
which causes stage `n` to use logger `vec[n]`.
`ParaReal.jl` provides the following observers and their associated loggers:

- [`CommunicatingObserver`](@ref):
  creates a [`CommunicatingLogger`](@ref) for every stage,
  which sends all events to the observer via a `RemoteChannel`
- [`TimingFileObserver`](@ref):
  creates a [`LazyFormatLogger`](@ref) for every sage,
  which adds a time stamp to every event and writes them to its own logfile

To implement a custom observer, define a method for [`getlogger(obs, n)`](@ref).
Note that the logger is being created (currently) on the managing process,
and then serialized and sent to the parareal executors via `Distributed.remotecall_wait`.
