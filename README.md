# ParaReal.jl

A [parareal](https://en.wikipedia.org/wiki/Parareal) orchestrator written in Julia.

[![Build Status](https://gitlab.mpi-magdeburg.mpg.de/jschulze/ParaReal.jl/badges/main/pipeline.svg)](https://gitlab.mpi-magdeburg.mpg.de/jschulze/ParaReal.jl/pipelines)
[![Coverage](https://gitlab.mpi-magdeburg.mpg.de/jschulze/ParaReal.jl/badges/main/coverage.svg)](https://gitlab.mpi-magdeburg.mpg.de/jschulze/ParaReal.jl/commits/main)

It has been tested on a [Slurm](https://slurm.schedmd.com/) allocation using 450 cores on 29 nodes.

Main features:

* Arbitrary problem and solution types
* Lazy data management (does not implicitly send data to calling process)
* Heterogeneous parareal values/iterates w.r.t. storage size and data type
* Parallel warm-up of solvers
* Logging solver start and stop times

## Getting started

The package can be installed from Julia's REPL:

```julia-repl
pkg> dev git@gitlab.mpi-magdeburg.mpg.de:jschulze/ParaReal.jl.git
```

Check out the demo and test files:

* `demo/riccati.jl` solves a differential Riccati equation (DRE) having a low-rank solution
* `demo/counting.jl` counts solver applications (demo for custom types)
* `test/problems/diffeq-ode.jl` solves a linear ordinary differential equation (ODE) using [OrdinaryDiffEq.jl]
* `test/problems/non-diffeq.jl` counts time discretization points (test for custom types)

[OrdinaryDiffEq.jl]: https://github.com/SciML/OrdinaryDiffEq.jl

## Acknowledgments

I would like to thank the code reviewers:

* Martin Köhler (https://github.com/grisuthedragon)
* Kathryn Lund (https://github.com/katlund)

## License

The ParaReal package is licensed under [MIT], see `LICENSE`.

[MIT]: https://spdx.org/licenses/MIT.html
