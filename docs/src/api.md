# API Reference

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
```

## Problem Interface

```@docs
initial_value
remake_prob
```

## Solution Interface

```@docs
dist
default_update!
```

## Pipeline Interface

```@docs
Pipeline
cancel_pipeline!
is_pipeline_cancelled
is_pipeline_failed
```

## Stage Interface

```@docs
value
solution
```

## Logging

```@docs
getlogger
CommunicatingObserver
CommunicatingLogger
TimingFileObserver
LazyFormatLogger
```
