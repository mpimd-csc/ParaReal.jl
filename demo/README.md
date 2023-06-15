# Demos

Before running any of the demos, instantiate the Julia environment:

```bash
julia --project -e "import Pkg; Pkg.instantiate()"
```

Execute the demos as follows.

```bash
julia --project counting.jl
julia --project riccati.jl
```

Alternatively, check out `docs/README.md` for how to build the documentation.
The documentation uses [Literate] to include some nicely rendered versions of
the demos in this directory.
Read these rendered pages to follow the demos at a slower pace.

[Literate]: https://github.com/fredrikekre/Literate.jl
