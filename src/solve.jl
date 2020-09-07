using Distributed: workers, @spawnat, RemoteChannel, procs
using Base.Threads: nthreads, @threads
using Base.Iterators: countfrom, repeat

function DiffEqBase.solve(
    prob::DiffEqBase.DEProblem,
    alg::ParaRealAlgorithm;
    ws = workers(),
    nt = Base.VERSION >= v"1.3" ? nthreads() : 1,
    maxiters = 10,
    )

    issubset(ws, procs()) || error("Unknown worker ids in `$workers`, no subset of `$(procs())`")
    Base.VERSION >= v"1.3" || nt == 1 || error("Multiple threads/tasks per worker require Julia v1.3")

    uType = typeof(prob.u0)
    uChannel = Channel{uType}
    uRemoteChannel = RemoteChannel{uChannel}
    createchan = () -> uChannel(1)

    @debug "Setting up connections"
    # Create connections between the pipeline stages:
    nsteps = length(ws) * nt
    conns = Vector{uRemoteChannel}(undef, nsteps+1)
    i = 1
    for w in ws
        for _ in 1:nt
            conns[i] = RemoteChannel(createchan, w)
            i += 1
        end
    end
    @assert i == nsteps+1
    conns[i] = conns[i-1]
    # conns[end] will never be accessed anyway

    # Create a connection back home for the local solutions:
    results = RemoteChannel(() -> Channel(nsteps))

    @debug "Starting worker tasks"
    # Wire up the pipeline:
    if Base.VERSION >= v"1.3"
        # TODO: use `@spawn` instead of `@threads for` for better composability.
        # For as long as tasks can't jump between threads, `@spawn` is quiet unreliable
        # in populating different threads. Therefore we stick to `@threads` for now.
        # Once the following PR is merged (maybe Julia v1.6), nested calls to `@threads`
        # will be parallelized as well.
        #
        # https://github.com/JuliaLang/julia/pull/36131#pullrequestreview-425193294
        tasks = asyncmap(ws, countfrom(1, nt)) do w, i
            _conns = @view conns[i:i+nt]
            @spawnat w begin
                @threads for j in 1:nt
                    in = _conns[j]
                    out = _conns[j+1]
                    _solve(prob, alg,
                           j+i-1, nsteps,
                           in, out,
                           results;
                           maxiters=maxiters)
                end
            end
        end
    else
        tasks = asyncmap(enumerate(ws)) do (i, w)
            @spawnat w _solve(prob, alg,
                              i, nsteps,
                              conns[i], conns[i+1],
                              results;
                              maxiters=maxiters)
        end
    end

    @debug "Sending initial value"
    # Kick off the pipeline:
    u0 = prob.u0
    firstchan = first(conns)
    put!(firstchan, u0)
    close(firstchan)

    # Make sure there were no errors:
    wait.(tasks)

    @debug "Collecting local solutions"
    sols = collect_solutions(results, nsteps)

    @debug "Reassembling global solution"
    # Assemble global solution:
    sol = assemble_solution(prob, alg, sols)
    return sol
end

function collect_solutions(results, nsteps)
    # Collect local solutions. Sorting them shouldn't be necessary,
    # but as there is networking involved, we're rather safe than sorry:
    step, sol = take!(results)
    sols = Vector{typeof(sol)}(undef, nsteps)
    sols[step] = sol
    for _ in 1:nsteps-1
        step, sol = take!(results)
        sols[step] = sol
    end
    sols
end

function assemble_solution(prob, alg, sols)
    tType = typeof(prob.tspan[1])
    uType = typeof(prob.u0)

    ts = Vector{tType}(undef, 0)
    us = Vector{uType}(undef, 0)
    retcodes = map(sols) do sol
        append!(ts, sol.t)
        append!(us, sol.u)
        sol.retcode
    end

    retcode = all(==(:Success), retcodes) ? :Success : :MaxIters
    DiffEqBase.build_solution(prob, alg, ts, us, retcode=retcode)
end
