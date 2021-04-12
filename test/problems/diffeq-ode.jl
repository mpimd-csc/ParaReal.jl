using Distributed, Test

verbose = isinteractive()
verbose && @info "Verifying setup"
nprocs() == 1 && addprocs(1)

using ParaReal, DifferentialEquations
@everywhere using ParaReal, DifferentialEquations

verbose && @info "Creating problem instance"
du = (u, _p, _t) -> u
u0 = [1.]
tspan = (0., 1.)
prob = ODEProblem(du, u0, tspan)

verbose && @info "Creating algorithm instance"
csolve = prob -> begin
    t0, tf = prob.tspan
    solve(prob, Euler(), dt=tf-t0)
end
fsolve = prob -> begin
    t0, tf = prob.tspan
    solve(prob, Euler(), dt=(tf-t0)/10)
end
alg = ParaReal.Algorithm(csolve, fsolve)

verbose && @info "Solving DiffEq ODEProblem"
n = 10
w = first(workers())
ids = fill(w, n)
sol = solve(prob, alg, workers=ids, maxiters=n)

# Compute reference solution elsewhere to "skip" compilation:
ref = @fetchfrom w solve(prob, Euler(), dt=1/10n)

@test sol isa DiffEqBase.AbstractODESolution
@test sol.retcode == :Success
@test sol[end] ≈ ref[end] rtol=1e-5
@test sol[end] ≈ [ℯ] rtol=0.01

