using Distributed, Test

verbose = isinteractive()
verbose && @info "Verifying setup"
nprocs() == 1 && addprocs(1)

using ParaReal, DifferentialEquations
@everywhere using ParaReal, DifferentialEquations, LinearAlgebra

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
alg = ParaReal.algorithm(csolve_ode2, fsolve_ode2)

verbose && @info "Solving DiffEq ODEProblem"
w = first(workers())
ids = fill(w, 10)
sol = solve(prob, alg, workers=ids, maxiters=5)

# Compute reference solution elsewhere to "skip" compilation:
ref = @fetchfrom w fsolve_ode2(prob)

@test sol isa DiffEqBase.AbstractODESolution
@test sol[end] ≈ ref[end] rtol=0.01
