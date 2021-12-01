function execute_stage(prob,
                alg::Algorithm,
                config::StageConfig;
                kwargs...
               )

    @unpack logger = config
    try
        with_logger(logger) do
            _execute_stage(prob, alg, config; kwargs...)
        end
    catch
        with_logger(logger) do
            @error "Stage failed" tag=:Failed n=config.n _group=:eventlog
        end
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

    @unpack n, N, prev, next, sol = config
    @info "Stage started" tag=:Started n type=:singleton _group=:eventlog

    if warmupc
        @info "Warming up coarse solver" tag=:WarmingUpC n type=:start _group=:eventlog
        csolve(prob, alg)
        @info "Coarse solver compiled and executed" tag=:WarmingUpC n type=:stop _group=:eventlog
    end
    if warmupf
        @info "Warming up fine solver" tag=:WarmingUpF n type=:start _group=:eventlog
        fsolve(prob, alg)
        @info "Fine solver compiled and executed" tag=:WarmingUpF n type=:stop _group=:eventlog
    end


    K = maxiters
    @assert K >= 1
    tspan = local_tspan(n, N, prob.tspan)

    _nconverged = 0
    u′ = u = u_coarse = u_fine = nothing
    local k, msg, fsol, converged

    for outer k in 1:min(n, K)
        # Receive initial value and initialize local problem instance
        msg, cancelled = receive_val(config, k)
        cancelled && return
        u_prev = nextvalue(msg)
        prob = remake_prob!(prob, alg, u_prev, tspan)

        # Compute coarse solution
        @info "Computing coarse solution" tag=:ComputingC n k type=:start _group=:eventlog
        csol = csolve(prob, alg)
        @info "Coarse solution ready" tag=:ComputingC n k type=:stop _group=:eventlog
        u_coarse′ = u_coarse
        u_coarse  = nextvalue(csol)

        # Compute refined solution k
        u′ = backup!(u′, u)
        @info "Computing parareal update" tag=:ComputingU n k type=:start _group=:eventlog
        u  = update_sol!(prob, alg, u, u_fine, u_coarse, u_coarse′)
        @info "Parareal update ready" tag=:ComputingU n k type=:stop _group=:eventlog

        # If the refined solution fulfills the convergence criterion,
        # perform a few iterations more to smooth out some more errors.
        if sol_converged(u′, u; tol=tol)
            _nconverged += 1
        else
            _nconverged = 0
        end
        converged = _nconverged >= nconverged

        # Send correction of coarse solution on to the next stage
        cancelled = send_val(config, u, converged)
        cancelled && return
        converged && break

        # Compute fine solution
        @info "Computing fine solution" tag=:ComputingF n k type=:start _group=:eventlog
        fsol = fsolve(prob, alg)
        @info "Fine solution ready" tag=:ComputingF n k type=:stop _group=:eventlog
        u_fine = nextvalue(fsol)

        # If the previous stage converged, all subsequent values of this stage
        # will equal the most recent u_fine. So skip ahead and send that one.
        didconverge(msg) && break
    end

    # Send final solution on to the next stage
    if !converged && k < K && (k == n || didconverge(msg))
        k += 1
        converged = true
        cancelled = send_val(config, u_fine, true)
        cancelled && return
    end

    @info "Storing local results" tag=:StoringResults n type=:singleton _group=:eventlog
    retcode = converged ? :Success : :MaxIters
    put!(sol, LocalSolution(n, k, fsol, retcode))
    @info "Stage finished" tag=:Done n k type=:singleton converged _group=:eventlog
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
    @info "Cancellation requested" tag=:Cancelled n=config.n k=0 type=:singleton _group=:eventlog
    return true
end

function receive_val(config::StageConfig, k)
    @info "Waiting for data" tag=:Waiting n=config.n k type=:start _group=:eventlog
    @unpack prev = config
    msg = take!(prev)
    cancelled = check_cancellation(config, msg)
    cancelled && return msg, true
    @info "New data received" tag=:Waiting n=config.n k type=:stop _group=:eventlog
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
