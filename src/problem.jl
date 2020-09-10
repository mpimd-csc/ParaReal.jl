"""
    initialvalue(prob)

Extract the initial value to kick off the ParaReal iterations.
Defaults to `prob.u0`.
"""
initialvalue(prob) = prob.u0

"""
    remake(prob; u0, tspan)

Create a new problem having the initial value `u0` and time span `tspan`.
"""
remake(prob::DiffEqBase.DEProblem; u0, tspan) = DiffEqBase.remake(prob; u0, tspan)
