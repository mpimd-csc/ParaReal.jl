using LinearAlgebra: norm

# TODO: put into worker setup / config:
# step, n,
# prev, next,
# tol
#
# Maybe also integrate worker state (mutable struct)

"""
    _solve(step, n, prob, prev, next)

# Arguments

* `prob::ODEProblem` global problem to be solved
* `alg::ParaRealAlgorithm`
* `step::Integer` current step in the pipeline
* `n::Integer` total number of steps in the pipeline
* `prev::AbstractChannel` where to get new `u0`-values from
* `next::AbstractChannel` where to put `u0`-values for the next pipeline step
"""
function _solve(prob::ODEProblem{uType},
                alg::ParaRealAlgorithm,
                step::Integer,
                n::Integer,
                prev::RemoteChannel{<:AbstractChannel{uType}},
                next::RemoteChannel{<:AbstractChannel{uType}};
                tol = 1e-5,
                maxiters = 100,
               ) where uType

    # Initialize local problem instance
    t0, tf = prob.tspan
    tspan = (((n-step+1)*t0 + (step-1)*tf)/n,
             ((n-step)  *t0 + (step)  *tf)/n)
    prob = remake(prob, tspan=tspan) # copies

    # Initialize solver algorithms
    coarse_integrator = alg.coarse(prob)
    fine_integrator = alg.fine(prob)

    # Allocate buffers
    coarse_u_old = similar(prob.u0)
    correction = similar(prob.u0)

    # Define variables to extend their scope
    coarse_u = nothing
    fine_u = nothing
    fine_sol = nothing

    converged = false
    niters = 0
    for u0 in prev
        niters += 1

        # Abort if maximum number of iterations is reached.
        niters > maxiters && break

        # Backupt old coarse solution if needed
        niters > 1 && copyto!(coarse_u_old, coarse_u)

        # Compute coarse solution
        reinit!(coarse_integrator, u0)
        coarse_sol = solve!(coarse_integrator)
        coarse_u = coarse_sol[end]

        # Hand correction of coarse solution on to the next workers.
        # Note that there is no correction to be done in the first iteration.
        if niters == 1
            step == n || put!(next, coarse_u)
        else
            alg.update!(correction, coarse_u, fine_u, coarse_u_old)
            diff = norm(correction - fine_u, 1) / norm(correction, 1)
            if diff < tol
                @debug "Worker converged" step niters
                converged = true
                break
            else
                step == n || put!(next, correction)
            end
        end

        # Compute fine solution
        reinit!(fine_integrator, u0)
        fine_sol = solve!(fine_integrator)
        fine_u = fine_sol[end]
    end

    if niters > maxiters
        @warn "Worker $step reached maximum number of iterations: $maxiters"
        #close(next)
        #return maxiters == 1 ? coarse_sol : fine_sol
    end

    if converged
        # If this worker converged, there is no need to pass on the next/same
        # solution again.
        close(next)
    else
        @debug "Previous worker converged; sending last fine solution" step niters
        # If instead the previous did converge, hand on the last fine solution
        # as the converged solution for this worker.
        put!(next, fine_u)
        close(next)
    end

    niters, fine_sol
end
