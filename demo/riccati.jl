# ```@meta
# CurrentModule=ParaReal
# ```
#
# # [Matrix Riccati Equation](@id riccati_demo)
#
# This example is meant to demonstrate
#
# * differently sized parareall iterates $U_n^k$,
#   where $n$ denotes the time slice, and $k$ denotes the parareal/Newton refinement, and
# * lazy data management, i.e. not to send (potentially huge amounts of) solution data back to the calling process,
#   as by default, every parareal stage $n$ is scheduled onto a separate process.
#
# Consider the Differential Riccati Equation (DRE)
#
# ```math
# \left\{
# \begin{aligned}
# E^T \dot X E &= -\big( C^T C + A^T X E + E^T X A - E^T X BB^T X E \big)
# \\
# E^T X(t_f) E &= \tfrac{1}{100} C^T C
# \end{aligned}
# \right.
# ```
#
# for autonomous system matrices $E,A,B,C$.
# In general, the solution $X(t) \in\mathbb R^{n\times n}$ is dense but has a low numerical rank.
# For a large state dimension it is therefore infeasible to store $X$ as a `Matrix`.
# We will use [`DifferentialRiccatiEquations`](https://gitlab.mpi-magdeburg.mpg.de/jschulze/DifferentialRiccatiEquations.jl)
# and its `LDLᵀ` data type that represents every solution value in the symmetric-indefinite low-rank factorization
#
# ```math
# X(t) = LDL^T
# ```
#
# where $L\in\mathbb R^{n\times r}$ is a skinny matrix, i.e. $r \ll n$.[^Lang2017]
#
# [^Lang2017]: See e.g. Section 2.1.4 and the references therein: Norman Lang. "Numerical methods for large-scale linear time-varying control systems and related differential matrix equations." PhD thesis. Technische Universität Chemnitz, 2017.
#
# Start by launching some worker processes and loading the necessary packages:

using Distributed
using DrWatson, UnPack, MAT
#md using SlurmClusterManager

addprocs(5) #src
#md addprocs(SlurmManager())

# Next, ensure the problem and solution types are known to all processes,
# and that they define the necessary interface:

@everywhere begin
    using DifferentialRiccatiEquations, ParaReal
    using DifferentialRiccatiEquations: DRESolution

    ParaReal.initial_value(p::GDREProblem) = p.X0
    ParaReal.value(sol::DRESolution) = last(sol.X)

    function ParaReal.remake_prob(p::GDREProblem, X0, tspan)
        GDREProblem(p.E, p.A, p.B, p.C, X0, tspan)
    end
end

# Furthermore, define the negation for the value type `LDLᵀ` in order to support [`default_update!`](@ref),
# and the norm of `LDLᵀ`, which is needed to assess the convergence of the solution values.
# Both methods are optional, as one may use a custom update function (cf. [`Algorithm`](@ref)),
# or not check for convergence (cf. [counting demo](@ref counting_demo)).

@everywhere begin
    using LinearAlgebra, SparseArrays

    ## needed for ParaReal.default_update!:
    function Base.:(-)(X::LDLᵀ{TL,TD}) where {TL,TD}
        Ls = X.Ls
        Ds = map(-, X.Ds)
        LDLᵀ{TL,TD}(Ls, Ds)
    end

    ## needed for convergence checks:
    function LinearAlgebra.norm(X::LDLᵀ)
        L, D = X
        norm((L'L)*D) # Frobenius
    end
end

# Define the coarse and fine solvers to be used in the parareal scheme:

@everywhere begin
    csolve(prob) = solve(prob, Ros1(); dt=prob.tspan[2] - prob.tspan[1])
    fsolve(prob) = solve(prob, Ros1(); dt=(prob.tspan[2] - prob.tspan[1])/100)
end

# Load the system matrices, define problem and algorithm instance,
# and solve the Riccati equation:

data = joinpath(pkgdir(DifferentialRiccatiEquations), "test", "Rail371.mat")
P = matread(data)
@unpack E, A, B, C = P
L = E \ collect(C')
D = spdiagm(fill(0.01, size(L, 2)))
X₀ = LDLᵀ(L, D)
tspan = (4500.0, 0.0)

prob = ParaReal.Problem(GDREProblem(E, A, B, C, X₀, tspan))
alg  = ParaReal.Algorithm(csolve, fsolve)
sol  = solve(prob, alg; rtol=1e-6, nconverged=2)

# The full trajectory of the fine solver may be extracted using [`solution`](@ref).
# As to not transfer the data to the calling process,
# use [`fetch_from_owner`](@ref) to write the results directly to disk from the processes holding the data:
#
# ```julia
# # Ensure output directly exists:
# dir = "out"
# mkpath(dir)
#
# @sync for sref in sol.stages
#     @async fetch_from_owner(sref) do s::ParaReal.Stage
#         lsol = solution(s)
#         tmin, tmax = extrema(sol.t)
#         fname = joinpath(dir, "t=$tmin:$max.h5")
#         # Write local solution `lsol` to `fname`, e.g. via
#         DrWatson.wsave(fname, sol)
#     end
# end
# ```
#
# The above works well as a blueprint for [`DrWatson._wsave`](https://juliadynamics.github.io/DrWatson.jl/v2.9/save/#Saving-Tools-1)
# for `ParaReal.Solution`.
