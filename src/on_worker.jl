# This file contains code that will only ever run on the worker processes.

function perform_step!(callback, Uᵏₙ₋₁, config::Config, stage::Stage)
    @unpack csolve, fsolve, update! = config.alg
    @unpack prob, n, k = stage
    stage.prob = prob = remake_prob(prob, Uᵏₙ₋₁, prob.tspan)

    @debug "Computing coarse solution" tag=:ComputingC n k type=:start _group=:eventlog
    Gᵏ = csolve(prob)
    @debug "Coarse solution ready" tag=:ComputingC n k type=:stop _group=:eventlog

    if k == 0
        # Report initial coarse solution:
        Uᵏ = value(Gᵏ)
    else
        # Report next Newton refinement:
        @unpack Uᵏ, Fᵏ⁻¹, Gᵏ⁻¹ = stage
        @debug "Computing parareal update" tag=:ComputingU n k type=:start _group=:eventlog
        Uᵏ = update!(Uᵏ, value(Gᵏ), value(Fᵏ⁻¹), value(Gᵏ⁻¹))
        @debug "Parareal update ready" tag=:ComputingU n k type=:stop _group=:eventlog
    end
    cancelled = callback(Uᵏ)
    cancelled && return false

    # Check convergence:
    ∞ = typemax(config.nconverged)
    if config.nconverged < ∞
        norm_Uᵏ = norm(Uᵏ)
        if k > 0
            @unpack Uᵏ⁻¹, norm_Uᵏ⁻¹ = stage
            @unpack atol, rtol = config
            norm_Uᵏ = norm(Uᵏ)
            if dist(Uᵏ, Uᵏ⁻¹) <= max(atol, max(norm_Uᵏ, norm_Uᵏ⁻¹) * rtol)
                stage.nconverged += 1
            else
                stage.nconverged = 0
            end
            stage.converged = stage.nconverged >= config.nconverged
        end
        stage.norm_Uᵏ⁻¹ = norm_Uᵏ
    end
    #stage.converged = stage.converged || k >= n

    # Compute next fine solution:
    @debug "Computing fine solution" tag=:ComputingF n k type=:start _group=:eventlog
    Fᵏ = fsolve(prob)
    @debug "Fine solution ready" tag=:ComputingF n k type=:stop _group=:eventlog

    # Prepare next step:
    stage.k = k + 1
    stage.Fᵏ⁻¹ = Fᵏ
    stage.Gᵏ⁻¹ = Gᵏ
    stage.Uᵏ⁻¹, stage.Uᵏ = Uᵏ, stage.Uᵏ⁻¹

    return stage.converged
end

# TODO: once #43852 is released (likely in v1.8),
# this has to be adjusted s.t. it doesn't get eliminated.
# This might require a PR against Compat.
# https://github.com/JuliaLang/julia/pull/43852
function perform_warmup(prob, config::Config, n::Int)
    @unpack csolve, fsolve = config.alg
    wc, wf = config.warmup
    if wc
        @debug "Warming up coarse solver" tag=:WarmingUpC n type=:start _group=:eventlog
        csolve(prob)
        @debug "Coarse solver compiled and executed" tag=:WarmingUpC n type=:stop _group=:eventlog
    end
    if wf
        @debug "Warming up fine solver" tag=:WarmingUpF n type=:start _group=:eventlog
        fsolve(prob)
        @debug "Fine solver compiled and executed" tag=:WarmingUpF n type=:stop _group=:eventlog
    end
    return nothing
end

# TODO:
function handle_cancellation(x, s::Stage)
    iscancelled(x) || return false
    n = s.n
    @warn "Cancellation requested" tag=:Cancelled n type=:singleton _group=:eventlog
    return true
end

function handle_msg(c::Cancellation, _::Config, stage::Stage)
    handle_cancellation(c, stage)
end

function handle_msg(msg::NextValue, config::Config, stage::Stage)
    # The number `k(n)` of parareal steps performed of a given stage `n` must
    # differ by at most 1 compared to its previous stage, i.e. `k(n) >= k(n-1) - 1`.
    # Therefore, queue the incoming (refined) value and only process it if necessary.
    @unpack U = msg
    @unpack queue, converged = stage
    push!(queue, U)
    converged && length(queue) <= 1 && return false

    # Compute refinements until convergence while previous ones are available.
    while !isempty(queue)
        Uₙ₋₁ = popfirst!(queue)
        converged = perform_step!(Uₙ₋₁, config, stage) do Uₙ
            send_val(stage, Uₙ)
        end
        converged && break
    end

    # If the maximum number of iterations is reached, pretend to have converged.
    # TODO: Do I need another message type?
    # TODO: k<K or k<=K ?
    stage.k < config.K && return false
    send_val(stage, Convergence())
    @unpack n, k, converged = stage
    @info "Stage finished" tag=:Done n k type=:singleton converged _group=:eventlog
    return true
end

function handle_msg(::Convergence, config::Config, stage::Stage)
    # If the current stage did converge already, don't send the true final
    # value, i.e. the most recent fine solution. This way, the next stage has
    # the chance to converge early (cf. comment in `handle_msg(::NextValue)`).
    @unpack k, n, converged = stage
    if !converged
        # The next refinement will equal the fine solution anyway,
        # so just send that directly.
        @unpack queue, Fᵏ⁻¹ = stage
        @assert isempty(queue)
        @assert k == n
        send_val(stage, value(Fᵏ⁻¹)) && return true
        converged = true
    end
    send_val(stage, Convergence()) && return true
    stage.converged = true
    @info "Stage finished" tag=:Done n k type=:singleton converged _group=:eventlog
    return true
end

function perform_nsteps!(
    prob,
    logger::Union{Nothing,AbstractLogger},
    config::Config,
    stageref::StageRef,
    Δk::Int,
)
    logger = something(logger, current_logger())
    stage = fetch(stageref)
    @unpack n, k = stage
    try
        with_logger(logger) do
            @info "Stage started" tag=:Started n type=:singleton _group=:eventlog
            k == 0 && perform_warmup(prob, config, n)
            # TODO: these k don't relate directly to the numebr of refinments computed.
            ks = k:k+Δk-1
            for k in ks
                msg = receive_val(stage, k)
                done = handle_msg(msg, config, stage)
                done && break
            end
        end
    catch ex
        with_logger(logger) do
            @error "Stage failed" tag=:Failed n type=:singleton _group=:eventlog
        end
        stage.ex = ex
        stage.st = stacktrace(catch_backtrace(), true)
    end
    return stageref
end

function receive_val(stage::Stage, k)
    @unpack prev, n = stage
    @debug "Waiting for data" tag=:Waiting n k type=:start _group=:eventlog
    # Do not remove cancellation messages, they shall clog the pipes:
    msg = fetch(prev)::Message
    iscancelled(msg) && return msg
    # The message available is not a cancellation message,
    # therefore remove it from the channel:
    _msg = take!(prev)::Message
    @assert msg === _msg
    @debug "New data received" tag=:Waiting n k type=:stop _group=:eventlog
    return msg
end

function send_val(stage::Stage, U)
    @unpack prev, next = stage
    handle_cancellation(prev, stage) && return true
    next === nothing && return false
    put!(next, Message(U))
    return false
end
