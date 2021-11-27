using ParaReal

struct TestProblem <: ParaReal.Problem tspan end
struct TestSolution end

ParaReal.remake_prob!(::TestProblem, _, _, tspan) = TestProblem(tspan)
ParaReal.initialvalue(::TestProblem) = [21]
ParaReal.nextvalue(::TestSolution) = [21]
