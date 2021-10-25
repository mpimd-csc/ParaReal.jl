# Benchmarks

## Time to first solution

How long does it take to load the `ParaReal` package and compile the routines
on all the workers? 

```bash
$ julia --project startup-single.jl
```

How is this affected by the number of workers?

`make` will schedule a bunch of measurement runs in a [Slurm] environment and
aggregate a report `startup-report.csv`. Individual timings will be stored in
e.g.  `out/startup_JOBID=123_N=4_T=1.csv`, where `N` is the number of nodes and
`T` the number of tasks per node, i.e. corresponding to a total of `N*T` worker
processes. The file names are compatible to `savename` and `parse_savename`
from [DrWatson].

[Slurm]: https://slurm.schedmd.com/
[DrWatson]: https://juliadynamics.github.io/DrWatson.jl/stable/
