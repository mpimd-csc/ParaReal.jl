# This file contains code that will only ever run on the managing process.

function manage_nsteps!(pl::Pipeline{ProcessesSchedule}, Δk::Int)
    @unpack prob, logger, config, stages = pl
    k = 0 # initial iteration
    delays = fill(0.05, 3)
    tasks = map(enumerate(stages)) do (n, stage)
        pid = stage.loc # process id
        l = getlogger(logger, stage.n)

        # Sometimes `remotecall_wait` fails for no apparent reason (maybe a
        # corrupted message, even though it's TCP), so retry if the stage
        # hasn't been launched already. Take `k==0` as a proxy for that, i.e.
        # retry if iteration 0 is still the "upcoming iteration".
        #
        # Unfortunately, this is untested as it should ideally never happen.
        #
        # https://discourse.julialang.org/t/how-to-debug-remotecall-wait-deserialization-failures/77864
        @async retry(
            () -> remotecall_wait(perform_nsteps!, pid, prob, l, config, stage, Δk);
            delays = delays,
            check = (attempt, err) -> begin
                @warn "Retrying stage $n (attempt #$attempt)" err
                stage.k == 0 # lazy!
            end,
        )()
    end

    # Wait for completion; cancel on failure:
    safewait(pl, tasks)

    return pl
end

function safewait(pl::Pipeline, tasks)
    @sync for (n, t) in enumerate(tasks)
        # This try-catch-block is technically not needed for the current design.
        # However, it proved to be handy if the package author screwed up again.
        @async try
            stage = fetch_stage(t)
            isfailed(stage) || return
            @warn "Cancelling pipeline due to failure on stage $n"
            cancel_pipeline!(pl)
        catch
            @error "Cancelling pipeline due to hard failure, maybe on stage $n"
            cancel_pipeline!(pl)
            rethrow()
        end
    end
end

fetch_stage(t::Union{Task,Future}) = fetch_stage(fetch(t))
fetch_stage(s::StageRef) = s

#= TODO: Base.iterate
function Base.iterate(pl::Pipeline, _=nothing)
    is_pipeline_done(pl) && return nothing
    manage_nsteps!(pl, 1)
    return nothing, nothing
end
=#

function init_pipes(schedule::ProcessesSchedule)
    @unpack workers = schedule

    issubset(workers, D.procs()) ||
        error("Unknown worker ids in `$workers`, no subset of `$(D.procs())`")
    allunique(workers) ||
        @warn "Multiple tasks per worker won't run in parallel. Use for debugging only."

    bufsize = 10 # TODO: find a better solution
    conns = map(workers) do w
        RemoteChannel(() -> Channel{Message}(bufsize), w)
    end

    return conns, workers
end

function init_problems(prob, N)
    U₀ = initial_value(prob)
    tspan = prob.tspan
    probs = map(1:N) do n
        tspan′ = local_tspan(n, N, tspan)
        remake_prob(prob, U₀, tspan′)
    end
    return probs
end

function init_stages(conns, locs, probs)
    N = length(locs)
    stages = StageRef.(locs)
    for n in 1:N-1
        prob = probs[n]
        prev = conns[n]
        next = conns[n+1]
        loc = locs[n]
        put!(stages[n], Stage(;
            prob,
            prev,
            next,
            loc,
            n,
        ))
    end
    put!(stages[N], Stage(;
        prob=probs[N],
        prev=conns[N],
        next=nothing,
        loc=locs[N],
        n=N,
    ))
    return stages
end
