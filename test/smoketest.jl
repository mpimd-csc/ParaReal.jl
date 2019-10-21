using Distributed
using Plots
using ParaReal # compile only once (currently broken)

nprocs() == 1 && addprocs()

@info "Loading modules"
@everywhere using ParaReal
@everywhere using DifferentialEquations

@everywhere include("problems.jl")
include("vanderpol.jl")

@info "Creating algorithm instance"
coarse = (prob) -> init(prob, Euler(), dt=prob.tspan[2]-prob.tspan[1])
fine = (prob) -> init(prob, RK4())
alg = ParaRealAlgorithm(coarse, fine)

@info "Solving"
sols, conns = solve(prob, alg)
