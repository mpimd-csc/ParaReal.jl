using Distributed, Test

verbose = isinteractive()
verbose && @info "Verifying setup"
nprocs() == 1 && addprocs(1)

using ParaReal, OrdinaryDiffEq
@everywhere using ParaReal, OrdinaryDiffEq

verbose && @info "Creating problem instance"
du = (u, _p, _t) -> u
u0 = [1.]
tspan = (0., 1.)
prob = ODEProblem(du, u0, tspan)

verbose && @info "Creating algorithm instance"
@everywhere begin
    csolve_ode(prob) = begin
        t0, tf = prob.tspan
        solve(prob, Euler(), dt=tf-t0)
    end
    fsolve_ode(prob) = begin
        t0, tf = prob.tspan
        solve(prob, Euler(), dt=(tf-t0)/10)
    end
end
alg = ParaReal.algorithm(csolve_ode, fsolve_ode)

verbose && @info "Solving DiffEq ODEProblem"
n = 10
w = first(workers())
ids = fill(w, n)
sol = solve(ParaReal.problem(prob), alg, workers=ids, maxiters=n)

# Compute reference solution elsewhere to "skip" compilation:
ref = @fetchfrom w solve(prob, Euler(), dt=1/10n)

@test sol isa DiffEqBase.AbstractODESolution
@test sol.retcode == :Success
@test sol[end] ≈ ref[end] rtol=1e-5
@test sol[end] ≈ [ℯ] rtol=0.01

