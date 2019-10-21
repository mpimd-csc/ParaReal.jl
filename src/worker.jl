# TODO: put into worker setup / config:
# step, n,
# in, out,
# tol
#
# Maybe also integrate worker state (mutable struct)

"""
    _solve(step, n, prob, in, out)

# Arguments

* `prob::ODEProblem` global problem to be solved
* `alg::ParaRealAlgorithm`
* `step::Integer` current step in the pipeline
* `n::Integer` total number of steps in the pipeline
* `in::AbstractChannel` where to get new `u0`-values from
* `out::AbstractChannel` where to put `u0`-values for the next pipeline step
"""
function _solve(prob::ODEProblem{uType},
                alg::ParaRealAlgorithm,
                step::Integer,
                n::Integer,
                in::RemoteChannel{<:AbstractChannel{uType}},
                out::RemoteChannel{<:AbstractChannel{uType}};
                tol = 1e-5,
               ) where uType

    # Initialize local problem instance
    u0 = take!(in)
    t0, tf = prob.tspan
    tspan = (((n-step+1)*t0 + (step-1)*tf)/n,
             ((n-step)  *t0 + (step)  *tf)/n)
    prob = remake(prob, u0=u0, tspan=tspan) # copies

    # Initialize solver algorithms
    coarse_integrator = alg.coarse(prob)
    fine_integrator = alg.fine(prob)

    # Compute first coarse solution and pass it on
    coarse_sol = solve!(coarse_integrator)
    coarse_u = coarse_sol[end]
    step == n || put!(out, coarse_u)

    # Compute fine solutions until convergence
    coarse_u_old = similar(u0)
    correction = similar(u0)
    niters = 0
    for u0 in in
        copy!(coarse_u_old, coarse_u)
        reinit!(coarse_integrator, u0)
        coarse_sol = solve!(coarse_integrator)
        coarse_u = coarse_sol[end]

        reinit!(fine_integrator, u0)
        fine_sol = solve!(fine_integrator)
        fine_u = fine_sol[end]

        alg.update!(correction, coarse_u, fine_u, coarse_u_old)
        diff = norm(correction - fine_u,1)/norm(correction,1)
        diff < tol && close(out) && break
        # TODO: tell previous worker that no more solutions will be read from `in`

        step == n || put!(out, correction)
        niters += 1
    end

    # Previous did converge, so did this worker
    step == n && put!(out, correction)
    close(out)

    niters, fine_sol # TODO: fix unknown fine_sol .. store in cache or something
end
