# API Reference

```@index
```

```@meta
CurrentModule = ParaReal
```

## CommonSolve

The high-level user interface

```julia
prob = ParaReal.Problem(...)
alg = ParaReal.Algorithm(...)
sol = solve(prob, alg; ...)
```

is implemented via [`CommonSolve`](https://juliahub.com/ui/Packages/CommonSolve/zEcGf/).
Internally, `solve(...)` is equivalent to `solve!(init(...))`.

```@docs
ParaReal.init
ParaReal.solve!
Problem
Algorithm
Solution
```

## Problem Interface

Implement methods for the following functions in order to support custom problem types:

```@docs
initial_value
remake_prob
```

## Solution Interface

To support custom solution types, you may want to define more efficient methods for

* [`dist`](@ref)
* `LinearAlgebra.norm`

and/or pass a custom `update!` function, cf. [`Algorithm`](@ref).

```@docs
dist
default_update!
value(::Any)
```

## Pipeline Interface

For most users, the [`solve`](@ref CommonSolve) interface from `CommonSolve` should suffice.
However, if you need access to e.g. intermediate states, use the `Pipeline` returned from [`init`](@ref).

```@docs
Pipeline
cancel_pipeline!
is_pipeline_cancelled
is_pipeline_failed
```

## Stage Interface

Given [`pl::Pipeline`](@ref Pipeline),
`pl.stages[n]` contains a handle to the parareal stage `n::Int`.
Use the following functions to access its information.
Check the demos for usage information.

```@docs
value(::Union{Stage,StageRef})
solution
```

## Logging

Check [Logging](@ref logging_usage) for usage information.

```@docs
getlogger
TimingFileObserver
LazyFormatLogger
CommunicatingObserver
CommunicatingLogger
```

## Utilities

```@docs
fetch_from_owner
```
