# Counting Solver Applications

In this rather abstract example we will count the applications of the coarse
and fine solvers within a parareal solve.
It is meant as a guideline of how what to implement/define for custom solution types.

!!! note "TODO: Implement proper solver statistics interface."
    Let user define some `stat(::MySolution)` or `stat(::Stage)`,
    that is collected over all parareal refinements.

# Implement Problem Interface

Define methods for

```
initial_value(::SomeProblem)
remake_prob(::SomeProblem, value, tspan)
```
