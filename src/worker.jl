# TODO: put into worker setup / config:
# step, n,
# in, out,
# tol
#
# Maybe also integrate worker state (mutable struct)

"""
    _solve(step, n, prob, in, out)

# Arguments

* `prob::ODEProblem` global problem to be solved
* `alg::ParaRealAlgorithm`
* `step::Integer` current step in the pipeline
* `n::Integer` total number of steps in the pipeline
* `in::AbstractChannel` where to get new `u0`-values from
* `out::AbstractChannel` where to put `u0`-values for the next pipeline step
"""
function _solve(prob::ODEProblem{uType},
                alg::ParaRealAlgorithm,
                step::Integer,
                n::Integer,
                in::AbstractChannel{uType},
                out::AbstractChannel{uType};
                tol = 1e-5,
               ) where uType

    # Initialize local problem instance
    u0 = take!(in)
    t0, tf = prob.tspan
    tspan = (((n-step+1)*t0 + (step-1)*tf)/n,
             ((n-step)  *t0 + (step)  *tf)/n)
    prob = remake(prob, u0=u0, tspan=tspan) # copies

    # Initialize solver algorithms
    coarse_integrator = alg.coarse(prob)
    fine_integrator = alg.fine(prob)

    # Compute first coarse solution and pass it on
    coarse_sol = solve!(coarse_integrator)
    coarse_u = coarse_sol[end]
    put(out, coarse_u)

    # Compute fine solutions until convergence
    coarse_u_old = similar(u0)
    correction = similar(u0)
    for u0 in _local(in)
        copy!(coarse_u_old, coarse_u)
        reinit!(coarse_integrator, u0)
        coarse_sol = solve!(coarse_integrator)
        coarse_u = coarse_sol[end]

        reinit!(fine_integrator, u0)
        fine_sol = solve!(fine_integrator)
        fine_u = fine_sol[end]

        alg.update!(correction, coarse_u, fine_u, coarse_u_old)
        diff = norm(correction - fine_u,1)/norm(correction,1)
        diff < tol && close(out) && break
        # TODO: tell previous worker that no more solutions will be read from `in`
    end

    # Previous did converge, so did this worker
    close(out)
end

"""
    _local(chan::AbstractChannel{T}) -> ::Channel{T}

Return a local version of `chan` to be used for iteration.
"""
function _local end

_local(chan::Channel) = chan

function _local(chan::RemoteChannel{T}, sz=0) where T
    c = Channel{T}(sz)
    @async begin
        while isopen(chan)
            wait(chan)
            put(c, take(chan))
        end
        close(c)
    end
    c
end
