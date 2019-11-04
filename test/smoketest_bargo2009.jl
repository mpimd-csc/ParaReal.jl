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

function plot_after_niters(i, p=plot(ref, vars=(1,2), label="ref"))
    rsols, conns = solve(prob, alg, maxiters=i)
    fsols = map(fetch, rsols)
    niters = map(x -> x[1], fsols)
    @show niters

    sols = map(x -> x[2], fsols)
    anchors = map(x -> x[1], sols)
    push!(anchors, sols[end][end]) # Note that for `i==1` this is a fine solution, not a coarse one.
    x = map(x -> x[1], anchors)
    y = map(x -> x[2], anchors)

    plot!(p, x, y, label="maxiters=$i")
    p
end

plot(plot_after_niters(1),
     plot_after_niters(2),
     plot_after_niters(3),
     plot_after_niters(4),
     layout = (2,2))
plot!(size=(1200,800))

