function execute_stage(prob,
                alg::Algorithm,
                config::StageConfig;
                kwargs...
               )

    try
        _execute_stage(prob, alg, config; kwargs...)
    catch
        _send_status_update(config, :Failed)
        rethrow()
    end
    nothing
end

function _execute_stage(
    prob,
    alg::Algorithm,
    config::StageConfig;
    maxiters = 10,
    tol = 1e-5,
    nconverged = 2,
    warmupc = true,
    warmupf = false,
)

    _send_status_update(config, :Started)
    if warmupc
        @debug "Warming up csolve" n
        _send_status_update(config, :WarmingUpC)
        csolve(prob, alg)
        _send_status_update(config, :DoneWarmingUpC)
    end
    if warmupf
        @debug "Warming up fsolve" n
        _send_status_update(config, :WarmingUpF)
        fsolve(prob, alg)
        _send_status_update(config, :DoneWarmingUpF)
    end

    @unpack n, N, prev, next, sol = config
    finalstage = n == N

    K = maxiters
    @assert K >= 1
    tspan = local_tspan(n, N, prob.tspan)

    @debug "Waiting for data" n pid=D.myid() tid=T.threadid()
    _nconverged = 0
    u′ = u = u_coarse = u_fine = nothing
    local k, msg, fsol, converged

    for outer k in 1:min(n, K)
        # Receive initial value and initialize local problem instance
        msg, cancelled = receive_val(config)
        cancelled && return
        u_prev = nextvalue(msg)
        prob = remake_prob!(prob, alg, u_prev, tspan)

        # Compute coarse solution
        @debug "Computing coarse solution" n k
        _send_status_update(config, :ComputingC)
        csol = csolve(prob, alg)
        _send_status_update(config, :DoneComputingC)
        u_coarse′ = u_coarse
        u_coarse  = nextvalue(csol)

        # Compute refined solution k
        u′ = backup!(u′, u)
        _send_status_update(config, :ComputingU)
        u  = update_sol!(prob, alg, u, u_fine, u_coarse, u_coarse′)
        _send_status_update(config, :DoneComputingU)

        # If the refined solution fulfills the convergence criterion,
        # perform a few iterations more to smooth out some more errors.
        if sol_converged(u′, u; tol=tol)
            _nconverged += 1
        else
            _nconverged = 0
        end
        converged = _nconverged >= nconverged

        # Send correction of coarse solution on to the next stage
        @debug "Sending value" n k
        cancelled = send_val(config, u, converged)
        cancelled && return
        converged && break

        # Compute fine solution
        @debug "Computing fine solution" n k
        _send_status_update(config, :ComputingF)
        fsol = fsolve(prob, alg)
        _send_status_update(config, :DoneComputingF)
        u_fine = nextvalue(fsol)

        # If the previous stage converged, all subsequent values of this stage
        # will equal the most recent u_fine. So skip ahead and send that one.
        didconverge(msg) && break

        @debug "Waiting for next value" n k
    end

    # Send final solution on to the next stage
    if !converged && k < K && (k == n || didconverge(msg))
        k += 1
        converged = true
        cancelled = send_val(config, u_fine, true)
        cancelled && return
    end

    if converged
        @debug "Converged successfully" n k
    end

    @debug "Storing results" n
    retcode = converged ? :Success : :MaxIters
    put!(sol, LocalSolution(n, k, fsol, retcode))
    @debug "Finished" n k
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

csolve(prob, alg::FunctionalAlgorithm) = alg.coarse(prob)
fsolve(prob, alg::FunctionalAlgorithm) = alg.fine(prob)

function check_cancellation(config::StageConfig, x)
    iscancelled(x) || return false
    _send_status_update(config, :Cancelled)
    return true
end

function receive_val(config::StageConfig)
    _send_status_update(config, :Waiting)
    @unpack prev = config
    msg = take!(prev)
    cancelled = check_cancellation(config, msg)
    cancelled && return msg, true
    _send_status_update(config, :DoneWaiting)
    return msg, false
end

function send_val(config::StageConfig, u, isfinal::Bool)
    @unpack prev, next, n, N = config
    finalstage = n == N

    cancelled = check_cancellation(config, prev)
    cancelled && return true
    msg = isfinal ? FinalValue(u) : NextValue(u)
    finalstage || put!(next, msg)
    return false
end

"""
    update_sol!(prob, alg, u::Nothing, u_fine::Nothing, u_coarse, u_coarse′::Nothing) -> u

Compute the first refined solution (`k=1`) where there are no previous
solutions `u_fine` and `u_coarse′`. Defaults to `copy(u_coarse)`.

When defining a new problem or algorithm, you may need to add a new method for this function.
"""
function update_sol!(_prob, _alg::Algorithm, u::Nothing, u_fine::Nothing, u_coarse, u_coarse′::Nothing)
    copy(u_coarse)
end

"""
    update_sol!(prob, alg, u, u_fine, u_coarse, u_coarse′) -> u

Compute the correction of the current `u_coarse` given the previous solutions
`u_fine` and `u_coarse′`. Defaults to `@. u = u_coarse + u_fine - u_coarse′`,
i.e. updating `u` in-place.

When defining a new problem or algorithm, you may need to add a new method for this function.
"""
function update_sol!(_prob, _alg, u, u_fine, u_coarse, u_coarse′)
    @. u = u_coarse + u_fine - u_coarse′
end

sol_converged(u′::Nothing, u; tol) = false
sol_converged(u′, u; tol) = isapprox(u′, u; rtol=tol)

backup!(x′, x) = copy(x)
backup!(x′::Nothing, x::Nothing) = nothing
backup!(x′::Array{T}, x::Array{T}) where {T} = copyto!(x′, x)
