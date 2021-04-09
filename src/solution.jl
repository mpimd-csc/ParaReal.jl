"""
Local solution over a single time slice
"""
struct LocalSolution{S}
    sol::S
    retcode::Symbol
end

"""
Global solution over the whole time span
"""
struct GlobalSolution{S}
    sols::Vector{S}
    retcodes::Vector{Symbol}
    retcode::Symbol

    function GlobalSolution(lsols::Vector{LocalSolution{S}}) where {S}
        sols = [s.sol for s in lsols]
        retcodes = [s.retcode for s in lsols]
        retcode = all(==(:Success), retcodes) ? :Success : :MaxIters
        new{S}(sols, retcodes, retcode)
    end
end

"""
    collect_solutions(pipeline::Pipeline)

Wait for the pipeline to finish and return a [`GlobalSolution`](@ref) of all
solutions for the smaller time slices (in order).

See [`Pipeline`](@ref) for the official interface.
"""
function collect_solutions(pipeline::Pipeline)
    # Check for errors:
    wait_for_pipeline(pipeline)

    @unpack results, workers = pipeline
    N = length(workers)

    # Collect local solutions. Sorting them shouldn't be necessary,
    # but as there is networking involved, we're rather safe than sorry:
    n, sol = take!(results)
    sols = Vector{typeof(sol)}(undef, N)
    sols[n] = sol
    for _ in 1:N-1
        n, sol = take!(results)
        sols[n] = sol
    end
    GlobalSolution(sols)
end

"""
    assemble_solution(prob, alg, sol) -> sol

Try to assemble a global solution of the same type as the local solutions.
Defaults to just returning the "internal" `sol::GlobalSolution`.
"""
assemble_solution(prob, alg, sol) = sol

"""
    nextvalue(sol)

Extract the initial value for the next ParaReal iteration.
Defaults to `sol[end]`.
"""
nextvalue(sol) = sol[end]
