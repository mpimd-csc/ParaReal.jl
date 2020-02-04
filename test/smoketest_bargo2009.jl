using Distributed
using Plots

nprocs() == 1 && addprocs()


@info "Loading modules"
@everywhere using ParaReal
@everywhere using DifferentialEquations
@everywhere using LinearAlgebra

@info "Creating problem instance"
@everywhere begin
    A = [-0.02 0.2
         -0.2 -0.02]
    f(du, u, _p, _t) = mul!(du, A, u)
end
u0 = [1., 0.]
tspan = (0., 100.)
prob = ODEProblem(f, u0, tspan)

@info "Creating algorithm instance"
δt = 0.1
δT = 1.0
coarse = (prob) -> init(prob, ImplicitEuler(), dt=δT, adaptive=false)
fine   = (prob) -> init(prob, ImplicitEuler(), dt=δt, adaptive=false)
alg = ParaRealAlgorithm(coarse, fine)

@info "Solving"
ref = solve!(fine(prob))

function plot_after_niters(i, p=plot(ref, vars=(1,2), label="ref"), lc=:orange)
    sol = solve(prob, alg, maxiters=i)

    # Plot the fine solutions
    plot!(p, sol, vars=(1,2), title="maxiters=$i", lc=lc)
    p
end

pp = map(plot_after_niters, 1:4)
plot(pp..., layout=(2,2), legend=:none)
plot!(size=(1200,800))
plot!(xlim=(-0.8,1.0), ylims=(-1.0,0.6), ticks=-1.0:0.2:1.0)

