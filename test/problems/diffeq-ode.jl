using Distributed, Logging, Test

verbose = isinteractive()
verbose && @info "Verifying setup"

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
alg = ParaReal.Algorithm(csolve_ode, fsolve_ode)

verbose && @info "Solving DiffEq ODEProblem"
n = 10
ids = fill(1, n)
schedule = ProcessesSchedule(ids)
sol = solve(ParaReal.Problem(prob), alg; schedule, maxiters=n, logger=NullLogger())

# Compute reference solution elsewhere to "skip" compilation:
ref = solve(prob, Euler(), dt=1/10n)
val = ParaReal.value(fetch(sol.stages[end]).Fᵏ⁻¹)

@test sol isa ParaReal.Solution
@test sol.retcode == :Success
@test val ≈ ref[end] rtol=1e-5
@test val ≈ [ℯ] rtol=0.01
