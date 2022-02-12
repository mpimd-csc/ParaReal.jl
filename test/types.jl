using ParaReal

struct TestProblem tspan end
struct TestSolution end

TestProblem() = TestProblem((0.0, 1.0))

ParaReal.remake_prob(::TestProblem, _, tspan) = TestProblem(tspan)
ParaReal.initial_value(::TestProblem) = [21]
ParaReal.value(::TestSolution) = [21]
