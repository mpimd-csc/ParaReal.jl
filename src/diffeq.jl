function DiffEqBase.solve(prob::DiffEqBase.DEProblem, alg::Algorithm; kwargs...)
    solve(prob, alg; kwargs...)
end

function remake_prob!(prob::DiffEqBase.DEProblem, _alg, u0, tspan)
    DiffEqBase.remake(prob; u0=u0, tspan=tspan) # copies :-(
end

function assemble_solution(
    prob::DiffEqBase.DEProblem,
    alg,
    gsol::GlobalSolution{S},
) where {S <: DiffEqBase.AbstractTimeseriesSolution}
    tType = typeof(prob.tspan[1])
    uType = typeof(initialvalue(prob))

    ts = Vector{tType}(undef, 0)
    us = Vector{uType}(undef, 0)
    for lsol in gsol.sols
        append!(ts, lsol.t)
        append!(us, lsol.u)
    end

    DiffEqBase.build_solution(prob, alg, ts, us, retcode=gsol.retcode)
end
