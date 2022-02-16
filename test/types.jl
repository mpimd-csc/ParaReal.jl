using ParaReal

struct TestProblem
    v
    tspan
end

struct TestSolution end

TestProblem() = TestProblem(nothing)
TestProblem(v) = TestProblem(v, (0., 42.))

ParaReal.remake_prob(::TestProblem, v, tspan) = TestProblem(v, tspan)
ParaReal.initial_value(p::TestProblem) = p.v
ParaReal.value(::TestSolution) = [21]
