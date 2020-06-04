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
coarse = (prob) -> init(prob, ImplicitEuler(), dt=1.0, adaptive=false)
fine   = (prob) -> init(prob, ImplicitEuler(), dt=0.1, adaptive=false)
alg = ParaRealAlgorithm(coarse, fine)

verbose && @info "Computing reference solution using fine solver"
ref = solve!(fine(prob))

verbose && @info "Solving using 1 thread per worker"
sol1 = solve(prob, alg;
             ws = workers()[1:10],
             nt = 1,
             maxiters=8)
@test isapprox(sol1[end], ref[end], rtol=1e-3)
@test sol1.retcode == :Success

verbose && @info "Solving using 2 threads per worker"
sol2 = solve(prob, alg;
             ws = workers()[1:5],
             nt = 2,
             maxiters=8)
@test isapprox(sol2[end], ref[end], rtol=1e-3)
@test sol2.retcode == :Success

