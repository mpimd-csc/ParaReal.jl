"""
    solve(prob, alg::ParaReal.Algorithm; kwargs...)

Solve `prob` using the parareal scheme `alg`.
Supported keyword arguments:

* `maxiters = 10`: maximum number of refinements
* `tol = 1e-5`: relative error bound to judge about preliminary convergence
* `nconverged = 2`: lower bound on successive converged refinements

Only if `nconverged` successive refinements show a relative change of
at most `tol`, the corresponding time slice is considered convergent.
"""
function solve(
    prob,
    alg::Algorithm;
    workers = workers(),
    kwargs...
    )

    D.myid() in workers &&
        error("Cannot use the managing process as a worker process (FIXME)")
    issubset(workers, D.procs()) ||
        error("Unknown worker ids in `$workers`, no subset of `$(D.procs())`")
    allunique(workers) ||
        @warn "Multiple tasks per worker won't run in parallel. Use for debugging only."

    @debug "Initializing global cache"
    pipeline = init_pipeline(workers)

    @debug "Starting worker tasks"
    run_pipeline!(pipeline, prob, alg; kwargs...)

    @debug "Collecting local solutions"
    sol = collect_solutions(pipeline)

    @debug "Reassembling global solution"
    return assemble_solution(prob, alg, sol)
end
