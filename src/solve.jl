using Distributed

import DiffEqBase: solve
using DiffEqBase: build_solution

function DiffEqBase.solve(prob::ODEProblem,
                          alg::ParaRealAlgorithm;
                          workers = workers(),
                          maxiters = 10,
                         )

    issubset(workers, procs()) || error("Unknown worker ids in `$workers`, no subset of `$(procs())`")

    uType = typeof(prob.u0)
    uChannel = Channel{uType}
    createchan = () -> uChannel(1)

    conns = asyncmap(workers) do w
        RemoteChannel(createchan, w)
    end
    push!(conns, RemoteChannel(createchan, myid()))

    steps = length(workers)
    results = map(1:steps) do i
        w = workers[i]
        in = conns[i]
        out = conns[i+1]
        @spawnat w _solve(prob, alg, i, steps, in, out; maxiters=maxiters)
    end

    u0 = prob.u0
    firstchan = first(conns)
    put!(firstchan, u0)
    close(firstchan)

    # TODO: drain and close all channels so that they can be gc'ed.
    # Wait for last solution

    # Collect and concat local solutions.
    tType = typeof(prob.tspan[1])
    ts = Vector{tType}(undef, 0)
    us = Vector{uType}(undef, 0)
    retcodes = map(results) do r
        sol = fetch(r)
        append!(ts, sol.t)
        append!(us, sol.u)
        sol.retcode
    end

    retcode = all(==(:Success), retcodes) ? :Success : :MaxIters
    build_solution(prob, alg, ts, us, retcode=retcode)
end
