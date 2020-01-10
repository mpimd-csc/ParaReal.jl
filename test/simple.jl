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

    verbose && @info "Starting ParaReal solver"
    kwargs = (maxiters = 7,
              workers = workers()[1:10])
    results_refs, conns = solve(prob, alg; kwargs...)
    verbose && @info "Waiting for solution ..."
    last_niters, last_sol = fetch(results_refs[end])

    @test isapprox(last_sol[end], ref[end], rtol=1e-3)
    @test_broken last_niters < 6
end

