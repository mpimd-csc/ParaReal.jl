@testset "simple (Bargo2009)" begin
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

    verbose && @info "Solving using ParaReal solver"
    kwargs = (maxiters = 8,
              workers = workers()[1:10])
    sol = solve(prob, alg; kwargs...)

    @test isapprox(sol[end], ref[end], rtol=1e-3)
    @test sol.retcode == :Success
end

