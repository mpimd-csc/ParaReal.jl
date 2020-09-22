DiffEqBase.solve(prob::DiffEqBase.DEProblem, alg::ParaRealAlgorithm; kwargs...) = solve(prob, alg; kwargs...)

function solve(
    prob,
    alg::ParaRealAlgorithm;
    workers = workers(),
    maxiters = 10,
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
    start_pipeline!(pipeline, prob, alg, maxiters=maxiters)

    @debug "Sending initial value"
    send_initial_value(pipeline, prob)

    # Make sure there were no errors:
    @debug "Waiting for completion"
    wait.(pipeline.tasks)

    @debug "Collecting local solutions"
    sol = collect_solutions(pipeline)

    @debug "Reassembling global solution"
    return assemble_solution(prob, alg, sol)
end
