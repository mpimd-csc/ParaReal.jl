using Distributed: workers, @spawnat, RemoteChannel, procs
using Base.Threads: nthreads, @threads
using Base.Iterators: countfrom, repeat

DiffEqBase.solve(prob::DiffEqBase.DEProblem, alg::ParaRealAlgorithm; kwargs...) = solve(prob, alg; kwargs...)

function solve(
    prob,
    alg::ParaRealAlgorithm;
    ws = workers(),
    nt = Base.VERSION >= v"1.3" ? nthreads() : 1,
    maxiters = 10,
    )

    issubset(ws, procs()) || error("Unknown worker ids in `$workers`, no subset of `$(procs())`")
    Base.VERSION >= v"1.3" || nt == 1 || error("Multiple threads/tasks per worker require Julia v1.3")

    u0 = initialvalue(prob)
    uType = typeof(u0)
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
    firstchan = first(conns)
    put!(firstchan, u0)
    close(firstchan)

    # Make sure there were no errors:
    wait.(tasks)

    @debug "Collecting local solutions"
    sol = collect_solutions(results, nsteps)

    @debug "Reassembling global solution"
    return assemble_solution(prob, alg, sol)
end
