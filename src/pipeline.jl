"""
    init(::ParaReal.Problem,
         ::ParaReal.Algorithm;
         kwargs...)

Initialize a pipeline to eventually run on the worker ids specified by
`workers`. Do not start the tasks executing the pipeline stages.

Returns a [`Pipeline`](@ref).

# Keyword Arguments

* `schedule::ParaReal.Schedule = ProcessesSchedule()`: specify how to
  distributed/schedule the tasks executing the stages
* `maxiters = 10`: maximum number of Newton refinements, `k <= K = maxiters`
* `nconverged = 2`: number of consequtive refinements without significant change;
  used to reason about convergence (more details below);
  set to `typemax(Int)` to disable convergence checks altogether
* `rtol::Float64 = size(iv, 1) * eps()`: relative error, where `iv = initial_value(prob.p)`;
  used to reason about convergence (more details below)
* `atol::Float64 = 0.0`: absolute error;
  used to reason about convergence (more details below)
* `logger = nothing`: where to log messages on the pipeline stages.
  If `nothing`, use `current_logger()` on the respective workers.
  Errors will be rethrown outside `with_logger(logger) do ... end`,
  i.e. handled by the global logger.
* `warmupc::Bool = true`: controls JIT-warmup of `csolve`, cf. [`Algorithm`](@ref)
* `warmupf::Bool = false`: controls JIT-warmup of `fsolve`, cf. [`Algorithm`](@ref)

# Convergence

A refinement `Uᵏ` showed no significant change if

```
dist(Uᵏ, Uᵏ⁻¹) <= max(atol, max(norm(Uᵏ), norm(Uᵏ⁻¹)) * rtol)
```

using [`dist`](@ref) and `LinearAlgebra.norm`.
As computing `norm(Uᵏ)` might be expensive, its value is cached between iterations.
Other than that, this works essentially like `isapprox`.

A stage `n` is considered to have converged, if

1. `>= nconverged` successive refinements showed no significant change, and
2. the previous stage `n-1` needed to compute at most 1 refinement more,
   i.e. `k(n) >= k(n-1) - 1`.

Due to the second criterion, `> nconverged` refinements without significant
change might have been computed.

Disable convergence checks by setting `nconverged` to `typemax(Int)`.
Then, neither `dist` nor `norm` will be computed;
they don't even require special methods for custom solution types.
"""
function init(prob::Problem, alg::Algorithm;
              schedule::Schedule=ProcessesSchedule(),
              maxiters::Int=10,
              nconverged::Int=2,
              rtol::Float64=size(initial_value(prob.p), 1) * eps(),
              atol::Float64=0.0,
              logger=nothing,
              warmupc::Bool=true,
              warmupf::Bool=false,
              )

    # Setup pipeline:
    conns, locs = init_pipes(schedule)
    N = length(conns)
    probs = init_problems(prob.p, N)
    stages = init_stages(conns, locs, probs)
    @assert length(locs) == length(probs) == length(stages) == N

    warmup = (warmupc, warmupf)
    config = Config(
        alg,
        N,
        maxiters,
        nconverged,
        atol,
        rtol,
        warmup,
    )

    pl = Pipeline(;
        prob=prob.p,
        schedule,
        config,
        stages,
        conns,
        logger,
    )

    return pl
end

"""
    solve!(::ParaReal.Pipeline)

Create and schedule the tasks executing the pipeline stages.
Send the problem's initial value and wait for the completion of all stages.
Throws an error if the pipeline failed.
"""
function solve!(pl::Pipeline)
    # Don't run the pipeline twice:
    if all(s -> s.k == 0, pl.stages)
        # Send initial value:
        c = first(pl.conns)
        put!(c, NextValue(initial_value(pl.prob)))

        # Ensure diagonal convergence, i.e. convergence after `k == n`:
        put!(c, Convergence())

        # Schedule and run pipeline tasks:
        manage_nsteps!(pl, 1 + pl.config.K)
    end

    # If any of the stages failed, collect all the errors and throw them:
    if isfailed(pl)
        ex = CompositeException()
        for s in pl.stages
            isfailed(s) || continue
            push!(ex, CapturedException(s.ex, s.st))
        end
        throw(ex)
    end

    sol = Solution(pl)
    return sol
end

"""
    cancel_pipeline!(::ParaReal.Pipeline)

Abandon all computations along the pipeline.
Do not wait for all the stages to stop.

See [`Pipeline`](@ref) for the official interface.
"""
function cancel_pipeline!(pl::Pipeline)
    pl.cancelled && return
    pl.cancelled = true
    for c in pl.conns
        put!(c, Cancellation())
    end
end
