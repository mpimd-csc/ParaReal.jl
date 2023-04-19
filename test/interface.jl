# This file is a part of ParaReal. License is MIT: https://spdx.org/licenses/MIT.html

using ParaReal
using ParaReal: value, solution
using Logging
using Test

# Dummy solution type:
struct Trajectory
    values::Vector{Int}
end

# Needed by default implementation of `value`:
Base.lastindex(t::Trajectory) = lastindex(t.values)
Base.getindex(t::Trajectory, i) = getindex(t.values, i)

# Compute solution:
csolve = p -> range(p.v; step=0.9, length=3)
fsolve = p -> range(p.v; step=1.0, length=3)
slope_prob = ParaReal.Problem(TestProblem(0))
slope_alg = ParaReal.Algorithm(csolve, fsolve)
slope_sol = solve(
    slope_prob,
    slope_alg;
    schedule=ProcessesSchedule([1, 1]),
    nconverged=typemax(Int),
    rtol=0.0,
    logger=NullLogger(),
)

# Prepare stage and stageref:
sr = first(slope_sol.stages)
s = fetch(sr)
@test sr isa ParaReal.StageRef
@test s isa ParaReal.Stage

@testset "solution(::$(typeof(x)))" for x in (sr, s)
    @test solution(x) == 0.0:1.0:2.0
end

@testset "value(::$(typeof(x)))" for x in (sr, s)
    @test value(x) == 2.0
    @test value(x) == value(solution(x))
end
