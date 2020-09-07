using LinearAlgebra: norm
using DiffEqBase: solution_new_retcode, remake

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
function _solve(prob::DiffEqBase.DEProblem,
                alg::ParaRealAlgorithm,
                step::Integer,
                n::Integer,
                prev::RemoteChannel{<:AbstractChannel{uType}},
                next::RemoteChannel{<:AbstractChannel{uType}},
                result::RemoteChannel;
                tol = 1e-5,
                maxiters = 100,
               ) where uType

    # Initialize local problem instance
    tspan = local_tspan(step, n, prob.tspan)

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
        prob = remake(prob, u0=u0, tspan=tspan) # copies :-(

        # Abort if maximum number of iterations is reached.
        niters > maxiters && break

        # Backupt old coarse solution if needed
        niters > 1 && copyto!(coarse_u_old, coarse_u)

        # Compute coarse solution
        coarse_sol = csolve(prob, alg)
        coarse_u = value(coarse_sol)

        # Hand correction of coarse solution on to the next workers.
        # Note that there is no correction to be done in the first iteration.
        if niters == 1
            step == n || put!(next, coarse_u)
        else
            alg.update!(correction, coarse_u, fine_u, coarse_u_old)
            diff = norm(correction - fine_u, 1) / norm(correction, 1)
            if diff < tol
                @debug "Worker $step/$n converged after $niters/$maxiters iterations"
                converged = true
                break
            else
                step == n || put!(next, correction)
            end
        end

        # Compute fine solution
        fine_sol = fsolve(prob, alg)
        fine_u = value(fine_sol)
    end

    if niters > maxiters
        @warn "Worker $step/$n reached maximum number of iterations: $maxiters"
        #close(next)
        #return maxiters == 1 ? coarse_sol : fine_sol
    end

    # If this worker converged, there is no need to pass on the
    # next/same solution again. If, instead, the previous worker
    # converged, closing `prev`, send the last fine solution to `next`
    # as the (eventually) converged solution of this worker.
    converged || step == n || put!(next, fine_u)
    step == n || close(next)

    retcode = niters > maxiters ? :MaxIters : :Success
    sol = solution_new_retcode(fine_sol, retcode)
    @debug "Worker $step/$n sending results"
    put!(result, (step, sol)) # Redo? return via `return` instead of channel
    @debug "Worker $step/$n finished"
    nothing
end

"""
    csolve(prob, alg) -> csol

Compute the low-accurary / cheap / coarse solution `csol` of the given problem `prob`.
"""
function csolve end

"""
    fsolve(prob, alg) -> fsol

Compute the high-accurary / fine solution `fsol` of the given problem `prob`.
"""
function fsolve end

csolve(prob, alg::ParaRealAlgorithm) = alg.coarse(prob)
fsolve(prob, alg::ParaRealAlgorithm) = alg.fine(prob)

"""
    value(sol) -> y

Extract the initial value `y` for the next ParaReal iteration.
"""
function value end

value(sol::DiffEqBase.DESolution) = sol[end]
