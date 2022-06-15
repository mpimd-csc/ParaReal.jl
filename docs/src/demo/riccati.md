# Matrix Riccati Equation

```@meta
CurrentModule=ParaReal
```

Consider the Differential Riccati Equation (DRE)

```math
\left\{
\begin{aligned}
E^T \dot X E &= -\big( C^T C + A^T X E + E^T X A - E^T X BB^T X E \big)
\\
E^T X(t_f) E &= \tfrac{1}{100} C^T C
\end{aligned}
\right.
```

for autonomous system matrices $E,A,B,C$.
In general, the solution $X(t) \in\mathbb R^{n\times n}$ is dense but has a low numerical rank.[^Lang2017]
For a large state dimension it is therefore infeasible to store $X$ as a `Matrix`.
We will use [`DifferentialRiccatiEquations`](https://gitlab.mpi-magdeburg.mpg.de/jschulze/DifferentialRiccatiEquations.jl)
and its `LDLᵀ` data type that represents every solution value as

```math
X(t) = LDL^T
```

where $L\in\mathbb R^{n\times r}$ is a skinny matrix, i.e. $r \ll n$.

[^Lang2017]: See e.g. Section 2.1.4 and the references therein: Norman Lang. "Numerical methods for large-scale linear time-varying control systems and related differential matrix equations." PhD thesis. Technische Universität Chemnitz, 2017.

Start by launching some worker processes and loading the necessary packages:

```julia
using Distributed
using DrWatson, UnPack, MAT
using SlurmClusterManager

addprocs(SlurmManager()) # or similar
```

Next, ensure the problem and solution types are known to all processes,
and that they define the necessary interface:

```julia
@everywhere begin
    using DifferentialRiccatiEquations, ParaReal
    using DifferentialRiccatiEquations: DRESolution

    ParaReal.initial_value(p::GDREProblem) = p.X0
    ParaReal.value(sol::DRESolution) = last(sol.X)

    function ParaReal.remake_prob(p::GDREProblem, X0, tspan)
        GDREProblem(p.E, p.A, p.B, p.C, X0, tspan)
    end
end
```

Furthermore, define the negation for the value type `LDLᵀ` in order to support [`default_update!`](@ref),
and the norm of `LDLᵀ`, which is needed to assess the convergence of the solution values.
Both methods are optional, as one may use a custom update function (cf. [`Algorithm`](@ref)),
or not check for convergence (cf. [counting demo](@ref counting_demo)).

```julia
@everywhere begin
    using LinearAlgebra, SparseArrays

    # needed for ParaReal.default_update!:
    function Base.:(-)(X::LDLᵀ{TL,TD}) where {TL,TD}
        Ls = X.Ls
        Ds = map(-, X.Ds)
        LDLᵀ{TL,TD}(Ls, Ds)
    end

    # needed for convergence checks:
    function LinearAlgebra.norm(X::LDLᵀ)
        L, D = X
        norm((L'L)*D) # Frobenius
    end
end
```

Define the coarse and fine solvers to be used in the parareal scheme:

```julia
@everywhere
    csolve(prob) = solve(prob, Ros1(); dt=prob.tspan[2] - prob.tspan[1])
    fsolve(prob) = solve(prob, Ros1(); dt=(prob.tspan[2] - prob.tspan[1])/100)
end
```

Finally, load the system matrices, define problem and algorithm instance,
and solve the Riccati equation:

```julia
P = matread(datadir("GDRE.mat"))
@unpack E, A, B, C = P
L = E \ collect(C')
D = spdiagm(fill(0.01, size(L, 2)))
X₀ = LDLᵀ(L, D)
tspan = (4500.0, 0.0)

prob = ParaReal.Problem(GDREProblem(E, A, B, C, X₀, tspan))
alg  = ParaReal.Algorithm(csolve, fsolve)
sol  = solve(prob, alg; rtol=1e-6, nconverged=2)
```
