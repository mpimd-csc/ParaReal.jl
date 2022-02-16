using Distributed, Logging, Test

verbose = isinteractive()
verbose && @info "Verifying setup"

using ParaReal, OrdinaryDiffEq
@everywhere using ParaReal, OrdinaryDiffEq, LinearAlgebra

verbose && @info "Creating problem instance"
@everywhere begin
    A = [-0.02 0.2
        -0.2 -0.02]
    f(du, u, _p, _t) = mul!(du, A, u)
end
u0 = [1., 0.]
tspan = (0., 100.)
prob = ODEProblem(f, u0, tspan)

verbose && @info "Creating algorithm instance"
@everywhere begin
    csolve_ode2(prob) = solve(prob, ImplicitEuler(), dt=1.0, adaptive=false)
    fsolve_ode2(prob) = solve(prob, ImplicitEuler(), dt=0.1, adaptive=false)
end
alg = ParaReal.Algorithm(csolve_ode2, fsolve_ode2)

verbose && @info "Solving DiffEq ODEProblem"
ids = fill(1, 10)
schedule = ProcessesSchedule(ids)
sol = solve(ParaReal.Problem(prob), alg; schedule, maxiters=5, logger=NullLogger())

# Compute reference solution elsewhere to "skip" compilation:
ref = fsolve_ode2(prob)
val = ParaReal.value(sol.stages[end].Fᵏ⁻¹)

@test sol isa ParaReal.Solution
@test val ≈ ref[end] rtol=0.01
