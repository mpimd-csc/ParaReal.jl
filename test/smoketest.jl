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
tspan = prob.tspan
dt = tspan[2] - tspan[1]
coarse = (prob) -> init(prob, Euler(), dt=dt)
fine = (prob) -> init(prob, Euler(), dt=dt/20)
alg = ParaRealAlgorithm(coarse, fine)

@info "Solving"
sols, conns = solve(prob, alg)
