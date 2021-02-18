function execute_stage(prob,
                alg::Algorithm,
                config::StageConfig;
                maxiters = 10,
                tol = 1e-5,
               )

    _send_status_update(config, :Started)
    @unpack step, nsteps, prev, next, results = config
    finalstage = step == nsteps

    # Initialize local problem instance
    tspan = local_tspan(step, nsteps, prob.tspan)

    # Allocate buffers
    _u = initialvalue(prob)
    u_coarse′ = similar(_u)
    u = similar(_u)
    u′ = similar(_u)

    # Define variables to extend their scope
    u_coarse = nothing
    u_fine = nothing
    fsol = nothing

    converged = false
    niters = 0
    @debug "Waiting for data" step pid=D.myid() tid=T.threadid()
    _send_status_update(config, :Waiting)
    for msg in prev
        iscancelled(msg) && (_send_status_update(config, :Cancelled); return)

        niters += 1
        @debug "Received new initial value" step niters
        _send_status_update(config, :Running)
        prob = remake_prob!(prob, alg, nextvalue(msg), tspan)

        # Abort if maximum number of iterations is reached.
        niters > maxiters && break

        # Backupt old coarse solution if needed
        niters > 1 && copyto!(u_coarse′, u_coarse)

        # Compute coarse solution
        u_coarse = nextvalue(csolve(prob, alg))
        iscancelled(prev) && (_send_status_update(config, :Cancelled); return)

        # Hand correction of coarse solution on to the next workers.
        # Note that there is no correction to be done in the first iteration.
        if niters == 1
            finalstage || put!(next, NextValue(u_coarse))
            copyto!(u′, u_coarse)
        else
            alg.update!(u, u_coarse, u_fine, u_coarse′)
            converged = isapprox(u′, u; rtol=tol)
            if converged
                @debug "Converged successfully" step niters
                _send_status_update(config, :Converged)
                break
            else
                finalstage || put!(next, NextValue(u))
                copyto!(u′, u)
            end
        end

        # Compute fine solution
        fsol = fsolve(prob, alg)
        u_fine = nextvalue(fsol)

        didconverge(msg) && break
    end

    if niters > maxiters
        @warn "Reached reached maximum number of iterations: $maxiters" step
    end

    # If this worker converged, there is no need to pass on the
    # next/same solution again. If, instead, the previous worker
    # converged, closing `prev`, send the last fine solution to `next`
    # as the (eventually) converged solution of this worker.
    finalstage || put!(next, FinalValue(u_fine))

    retcode = niters > maxiters ? :MaxIters : :Success
    sol = LocalSolution(fsol, retcode)
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
