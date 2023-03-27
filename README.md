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

