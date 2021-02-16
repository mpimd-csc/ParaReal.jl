function execute_stage(prob,
                alg::Algorithm,
                config::StageConfig;
                maxiters = 10,
                tol = 1e-5,
               )

    _send_status_update(config, :Started)
    @unpack step, nsteps, prev, next, results, ctx = config
    finalstage = step == nsteps

    # Initialize local problem instance
    tspan = local_tspan(step, nsteps, prob.tspan)

    # Allocate buffers
    u = initialvalue(prob)
    coarse_u_old = similar(u)
    correction = similar(u)

    # Define variables to extend their scope
    coarse_u = nothing
    fine_u = nothing
    fine_sol = nothing

    converged = false
    niters = 0
    @debug "Waiting for data" step pid=D.myid() tid=T.threadid()
    _send_status_update(config, :Waiting)
    iscanceled(ctx) && (_send_status_update(config, :Cancelled); return)
    for u0 in prev
        niters += 1
        @debug "Received new initial value" step niters
        _send_status_update(config, :Running)
        prob = remake(prob, u0=u0, tspan=tspan) # copies :-(

        # Abort if maximum number of iterations is reached.
        niters > maxiters && break

        # Backupt old coarse solution if needed
        niters > 1 && copyto!(coarse_u_old, coarse_u)

        # Compute coarse solution
        coarse_sol = csolve(prob, alg)
        coarse_u = nextvalue(coarse_sol)
        iscanceled(ctx) && (_send_status_update(config, :Cancelled); return)

        # Hand correction of coarse solution on to the next workers.
        # Note that there is no correction to be done in the first iteration.
        if niters == 1
            finalstage || put!(next, coarse_u)
        else
            alg.update!(correction, coarse_u, fine_u, coarse_u_old)
            diff = norm(correction - fine_u, 1) / norm(correction, 1)
            if diff < tol
                @debug "Converged successfully" step niters
                _send_status_update(config, :Converged)
                converged = true
                break
            else
                finalstage || put!(next, correction)
            end
        end

        # Compute fine solution
        fine_sol = fsolve(prob, alg)
        fine_u = nextvalue(fine_sol)
        iscanceled(ctx) && (_send_status_update(config, :Cancelled); return)
    end

    if niters > maxiters
        @warn "Reached reached maximum number of iterations: $maxiters" step
    end

    # If this worker converged, there is no need to pass on the
    # next/same solution again. If, instead, the previous worker
    # converged, closing `prev`, send the last fine solution to `next`
    # as the (eventually) converged solution of this worker.
    converged || finalstage || put!(next, fine_u)
    finalstage || close(next)

    retcode = niters > maxiters ? :MaxIters : :Success
    sol = LocalSolution(fine_sol, retcode)
    @debug "Sending results" step
    put!(results, (step, sol)) # Redo? return via `return` instead of channel
    @debug "Finished" step niters
    _send_status_update(config, :Done)
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

csolve(prob, alg::Algorithm) = alg.coarse(prob)
fsolve(prob, alg::Algorithm) = alg.fine(prob)
