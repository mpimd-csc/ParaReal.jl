import .DiffEqBase

function remake_prob!(prob::DiffEqBase.DEProblem, _alg, u0, tspan)
    DiffEqBase.remake(prob; u0=u0, tspan=tspan) # copies :-(
end
