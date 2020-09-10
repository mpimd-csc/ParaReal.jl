"""
    initialvalue(prob)

Extract the initial value to kick off the ParaReal iterations.
Defaults to `prob.u0`.
"""
initialvalue(prob) = prob.u0
