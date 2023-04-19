# This file is a part of ParaReal. License is MIT: https://spdx.org/licenses/MIT.html

using Distributed, SlurmClusterManager

if nprocs() == 1
    if "SLURM_JOBID" in keys(ENV) || "SLURM_JOB_ID" in keys(ENV)
        @info "Spawning workers using Slurm"
        addprocs(SlurmManager())
    else
        @info "Spawning workers locally"
        addprocs(4; exeflags=["--project"])
    end
    @info "Connecting to workers"
    @everywhere 1+1
end

@info "Using project" project=map(w -> remotecall_fetch(Base.active_project, w), procs())

tic() = time_ns()
toc(t) = (time_ns() - t) / 1e9

@info "Loading ParaReal"
t_load = @elapsed(@everywhere using ParaReal)
@info "... took $t_load seconds"
@info "Loading remaining modules"
@everywhere begin
    using OrdinaryDiffEq
    using LinearAlgebra

    nt = parse(Int, get(ENV, "SLURM_CPUS_PER_TASK", "1"))
    BLAS.set_num_threads(nt)
end

@info "Creating problem instance (Bargo2009)"
@everywhere begin
    A = [-0.02 0.2
         -0.2 -0.02]
    f(du, u, _p, _t) = mul!(du, A, u)
end
u0 = [1., 0.]
tspan = (0., 100.)
prob = ParaReal.Problem(ODEProblem(f, u0, tspan))

@info "Creating algorithm instance"
@everywhere begin
    csolve(prob) = solve(prob, ImplicitEuler(), dt=1.0, adaptive=false)
    fsolve(prob) = solve(prob, ImplicitEuler(), dt=0.1, adaptive=false)
end
alg = ParaReal.Algorithm(csolve, fsolve)

@info "Starting solver"
t_solve = @elapsed(sol = solve(prob, alg, maxiters=5))
@info "... took $t_solve seconds"

println(t_load, ", ", t_solve)
