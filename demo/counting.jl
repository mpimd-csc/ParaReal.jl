# ```@meta
# CurrentModule=ParaReal
# ```
#
# # [Counting Solver Applications](@id counting_demo)
#
# In this rather abstract example we will count the applications of the coarse
# and fine solvers within a parareal solve.
# It is meant as a guideline of what to implement/define for custom problem and solution types.
#
# Start by launching some worker processes and loading the necessary packages:

using ParaReal
using Distributed: addprocs, workers, @everywhere

addprocs(3)
@everywhere using ParaReal

# Next, define the problem type and ensure that its definition is available on all processes.
# The only requirement to the problem type is to have a tspan field.[^1]
# In the context of ODEs, this should not clash with any other notation.
#
# [^1]: Alternatively, it must support `getproperty(prob, :tspan)`.

@everywhere begin
    struct SomeProblem
        v
        tspan
    end
    ParaReal.initial_value(p::SomeProblem) = p.v
    ParaReal.remake_prob(::SomeProblem, v, tspan) = SomeProblem(v, tspan)
end

# The solution type will hold counters of the applications of the fine solver $F$ and coarse solver $G$:

@everywhere begin
    struct Counters
        F::Int
        G::Int
    end
    ParaReal.value(c::Counters) = c

    ## Needed by default parareal update implementation:
    Base.:(+)(c1::Counters, c2::Counters) = Counters(c1.F + c2.F, c1.G + c2.G)
    Base.:(-)(c::Counters) = c
end

# Define the solver functions, problem instance, and execute the parareal pipeline.
# The solver functions are defined as closures, such that they can be serialized and transferred to the worker processes.
# Note that this code is only executed on the managing process:

inc_F = (p::SomeProblem) -> Counters(p.v.F + 1, p.v.G)
inc_G = (p::SomeProblem) -> Counters(p.v.F, p.v.G + 1)
tspan = (0., 42.) # does not matter here
prob = SomeProblem(Counters(0, 0), tspan)
sol = solve(
    ParaReal.Problem(prob),
    ParaReal.Algorithm(inc_G, inc_F);
    schedule=ProcessesSchedule(workers()), # default
    maxiters=2,
    ## disable convergence checks, which call norm(::Counters)
    nconverged=typemax(Int),
    ## do not evaluate default rtol, which calls size(::Counters, 1)
    rtol=0.0,
)

# Lastly, extracting the final values $U_1^1$, $U_2^2$, and $U_3^2$ using [`value`](@ref value(::Stage)) yields

using ParaReal: value
value(sol.stages[1]) # U₁¹ or Counters(1, 0)  #md
value(sol.stages[2]) # U₂² or Counters(2, 0)  #md
value(sol.stages[3]) # U₃² or Counters(7, 10) #md

using Test #src
@test value(sol.stages[1]) == Counters(1, 0)  #src
@test value(sol.stages[2]) == Counters(2, 0)  #src
@test value(sol.stages[3]) == Counters(7, 10) #src

# since
#
# ```math
# \begin{align*}
# U_1^1 &= F(U_0) \\
# U_2^2 &= F(F(U_0)) \\
# U_3^2 &= G(F(F(U_0))) + F(U_2^1) - G(U_2^1)
# \end{align*}
# ```
#
# and
#
# ```math
# U_2^1 = G(F(U_0)) + F(G(U_0)) - G(G(U_0)),
# ```
#
# which results in $3+2\cdot 2=7$ applications of $F$ and $2+2\cdot 4=10$ applications of $G$ to compute $U_3^2$.
