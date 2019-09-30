using Distributed

nprocs() == 1 && addprocs()

using ParaReal
using DifferentialEquations

include("problems.jl")
include("vanderpol.jl")

coarse = (prob) -> init(prob, Euler())
fine = (prob) -> init(prob, RK4())
alg = ParaRealAlgorithm(coarse, fine)

solve(prob, alg)
