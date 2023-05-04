# Building the docs locally

To build the documentation locally, run the following.

```bash
julia --project -e 'import Pkg; Pkg.instantiate(); Pkg.develop(path="..")'
julia --project make.jl
```

To view the rendered documentation, run

```bash
cd build
python3 -m http.server
```

and open `http://0.0.0.0:8000/` in your browser of choice.

> **Warning**
> You must never commit changes made to `Project.toml`, because this package
> may not have been registered, yet. Also, you must never commit the
> `Manifest.toml`, as that is specific to the Julia version used to build the
> docs.

Before switching Julia versions, make sure to revert your changes.

```bash
git restore .
rm Manifest.toml
```
