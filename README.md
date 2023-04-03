# ParaReal.jl

A [parareal](https://en.wikipedia.org/wiki/Parareal) orchestrator written in Julia.

[![Build Status](https://gitlab.mpi-magdeburg.mpg.de/jschulze/ParaReal.jl/badges/master/pipeline.svg)](https://gitlab.mpi-magdeburg.mpg.de/jschulze/ParaReal.jl/pipelines)
[![Coverage](https://gitlab.mpi-magdeburg.mpg.de/jschulze/ParaReal.jl/badges/master/coverage.svg)](https://gitlab.mpi-magdeburg.mpg.de/jschulze/ParaReal.jl/commits/master)

It has been tested on a [Slurm](https://slurm.schedmd.com/) allocation using 450 cores on 29 nodes.

Main features:

* Arbitrary problem and solution types, cf. [counting demo](@ref counting_demo)
* Lazy data management (does not implicitly send data to calling process), cf. [Riccati demo](@ref riccati_demo)
* Heterogeneous parareal values/iterates w.r.t. storage size and data type
* Parallel warm-up of solvers
* Logging solver start and stop times

## Getting started

The package can be installed from Julia's REPL:

```
pkg> dev git@gitlab.mpi-magdeburg.mpg.de:jschulze/ParaReal.jl.git
```

Check out the demo and test files:

* `demo/riccati.jl` solves a differential Riccati equation (DRE) having a low-rank solution
* `demo/counting.jl` counts solver applications (demo for custom types)
* `test/problems/diffeq-ode.jl` solves a linear ordinary differential equation (ODE) using [OrdinaryDiffEq.jl]
* `test/problems/non-diffeq.jl` counts time discretization points (test for custom types)

[OrdinaryDiffEq.jl]: https://github.com/SciML/OrdinaryDiffEq.jl

