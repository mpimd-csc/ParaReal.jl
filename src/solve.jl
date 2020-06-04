using Distributed: workers, @spawnat, RemoteChannel, procs
using Base.Threads: nthreads, @spawn
using Base.Iterators: countfrom, repeat

import DiffEqBase: solve
using DiffEqBase: build_solution

function DiffEqBase.solve(
    prob::ODEProblem,
    alg::ParaRealAlgorithm;
    ws = workers(),
    nt = nthreads(),
    maxiters = 10,
    )

    issubset(ws, procs()) || error("Unknown worker ids in `$workers`, no subset of `$(procs())`")

    uType = typeof(prob.u0)
    uChannel = Channel{uType}
    uRemoteChannel = RemoteChannel{uChannel}
    createchan = () -> uChannel(1)

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

    # Wire up the pipeline:
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
    #=
    # Wire up the pipeline:
    tasks = asyncmap(repeat(ws, inner=nt),
                     countfrom(1)) do w, i
        in = conns[i]
        out = conns[i+1]
        # Create a task to hop off thread 1.
        @spawnat w wait(
            @spawn _solve(prob, alg,
                          i, nsteps,
                          in, out,
                          results;
                          maxiters=maxiters))
    end
    =#

    @info "Sending initial value"
    # Kick off the pipeline:
    u0 = prob.u0
    firstchan = first(conns)
    put!(firstchan, u0)
    close(firstchan)

    # Make sure there were no errors:
    wait.(tasks)

    @info "Collecting"
    # Collect local solutions. Sorting them shouldn't be necessary,
    # but as there is networking involved, we're rather safe than sorry:
    sols = Vector(undef, nsteps)
    for _ in 1:nsteps
        step, sol = take!(results)
        sols[step] = sol
    end

    @info "Assembling"
    # Assemble global solution:
    tType = typeof(prob.tspan[1])
    ts = Vector{tType}(undef, 0)
    us = Vector{uType}(undef, 0)
    retcodes = map(sols) do sol
        append!(ts, sol.t)
        append!(us, sol.u)
        sol.retcode
    end

    retcode = all(==(:Success), retcodes) ? :Success : :MaxIters
    build_solution(prob, alg, ts, us, retcode=retcode)
end
