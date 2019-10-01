using Distributed

import DiffEqBase: solve
using DiffEqBase

function DiffEqBase.solve(prob::ODEProblem,
                          alg::ParaRealAlgorithm;
                          workers = procs(),
                         )

    issubset(workers, procs()) || error("Unknown worker ids in `$workers`, no subset of `$(procs())`")

    # TODO
    # communicate the initial problem to all workers
    # restrict to local problem: prob = localpart(prob)
    # initialize coarse and fine integrators: maybe request initializer function that just receives the local problem
    #
    # close remote channels when local/fine solution did converge

    uType = typeof(prob.u0)
    uChannel = Channel{uType}
    createchan = () -> uChannel(1)

    conns = asyncmap(workers) do w
        RemoteChannel(createchan, w)
    end
    push!(conns, RemoteChannel(createchan, myid()))

    # TODO: killswitches similar to conns

    steps = length(workers)
    results = map(1:steps) do i
        w = workers[i]
        in = conns[i]
        out = conns[i+1]
        @spawnat w _solve(prob, alg, i, steps, in, out)
    end

    u0 = prob.u0
    firstchan = first(conns)
    put!(firstchan, u0)
    close(firstchan)

    # TODO: drain and close all channels so that they can be gc'ed.
    # Wait for last solution
    results
end

function worker(input, output, prob, alg::ParaRealAlgorithm, first::Bool, last::Bool)
    it = 0
    coarse_sol = 42
    for u0 in input
        it += 1

        # Propagate new initial value to local integrators
        reinit!(coarse_integrator, u0)
        coarse_sol = perform_step!(coarse_integrator)

        reinit!(fine_integrator, u0)
        coarse_sol = solve!(fine_integrator) # TODO: extract only final value

        it == 1 && put!(output, coarse_sol) && continue

        converged = true
        converged && close(output)
    end
    # previous worker did converge; last chance for an update
    close(output)

    true, diff, it
end
