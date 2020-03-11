using Distributed

if nprocs() == 1
    @info "Spawning workers"
    addprocs(4)
    @info "Connecting to workers"
    @everywhere 1+1
end

t = zeros(2)

@info "Loading ParaReal"
_, t[1], _, _, _ = @timed begin
    @everywhere using ParaReal
end
@info "... took $(t[1])"
@info "Loading remaining modules"
@everywhere begin
    using DifferentialEquations
    using LinearAlgebra

    BLAS.set_num_threads(1)
end

@info "Creating problem instance (Bargo2009)"
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

@info "Starting solver"
_, t[2], _, _, _ = @timed sol = solve(prob, alg, maxiters=5)
@info "... took $(t[2])"
