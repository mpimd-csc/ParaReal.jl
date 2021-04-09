"""
    initialvalue(prob)

Extract the initial value to kick off the ParaReal iterations.
Defaults to `prob.u0`.
"""
initialvalue(prob) = prob.u0

"""
    remake_prob!(prob, alg, u0, tspan)

Create a new problem having the initial value `u0` and time span `tspan`.
May update `prob` in-place. Return `prob`.
"""
function remake_prob! end

function remake_prob!(prob::DiffEqBase.DEProblem, _alg, u0, tspan)
    DiffEqBase.remake(prob; u0=u0, tspan=tspan) # copies :-(
end