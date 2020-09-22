@everywhere using DifferentialEquations
@everywhere using LinearAlgebra: mul!

verbose && @info "Verifying setup"
@assert nworkers() >= 10
@assert nthreads() >= 2

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
coarse = prob -> solve(prob, ImplicitEuler(), dt=1.0, adaptive=false)
fine   = prob -> solve(prob, ImplicitEuler(), dt=0.1, adaptive=false)
alg = ParaRealAlgorithm(coarse, fine)

verbose && @info "Computing reference solution using fine solver"
ref = fine(prob)

verbose && @info "Solving using 1 thread per worker"
ids1 = workers()[1:10]
sol1 = solve(prob, alg;
             workers=ids1,
             maxiters=8)
@testset "1 thread/worker" begin
    @test isapprox(sol1[end], ref[end], rtol=1e-3)
    @test sol1.retcode == :Success
end

if Base.VERSION >= v"1.3"

verbose && @info "Solving using 2 threads per worker"
ids2 = repeat(workers()[1:5], inner=2)
sol2 = solve(prob, alg;
             workers=ids2,
             maxiters=8)
@testset "2 threads/worker" begin
    @test isapprox(sol2[end], ref[end], rtol=1e-3)
    @test sol2.retcode == :Success
end

end
