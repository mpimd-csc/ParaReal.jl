import .DiffEqBase

function remake_prob(prob::DiffEqBase.DEProblem, u0, tspan)
    DiffEqBase.remake(prob; u0=u0, tspan=tspan)
end

initial_value(prob::DiffEqBase.DEProblem) = prob.u0
