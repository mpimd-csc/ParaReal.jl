using Distributed

import DiffEqBase: solve
using DiffEqBase

function DiffEqBase.solve(prob::ODEProblem,
                          alg::ParaRealAlgorithm;
                          workers = workers(),
                          maxiters = 100,
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
    results, conns
end
