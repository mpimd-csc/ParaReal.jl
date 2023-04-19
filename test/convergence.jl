# This file is a part of ParaReal. License is MIT: https://spdx.org/licenses/MIT.html

using LinearAlgebra
using Logging
using ParaReal
using Test

# count applications of csolve and fsolve:
struct Counters
    F::Int
    G::Int
end

Counters() = Counters(0, 0)
ParaReal.value(s::Counters) = s

# needed for default_update!
Base.:(-)(c::Counters) = c
Base.:(+)(c1::Counters, c2::Counters) = Counters(c1.F + c2.F, c1.G + c2.G)

count_fsolve = p -> Counters(p.v.F+1, p.v.G)
count_csolve = p -> Counters(p.v.F, p.v.G+1)

counting_prob = ParaReal.Problem(TestProblem(Counters()))
counting_alg = ParaReal.Algorithm(count_csolve, count_fsolve)

schedule = ProcessesSchedule([1, 1, 1])
kwargs = (;
    schedule,
    rtol=0.0, # don't evaluate size(_, ::Int)
    logger=NullLogger(), # disable logging
)

@testset "K=$K ($desc)" for (K, desc) in zip(
    [4, 3], # K
    ["not reached", "sufficient"], # description
)
    sol = solve(counting_prob, counting_alg;
                maxiters=K,
                # disable convergence checks; don't evaluate norm(::Counters)
                nconverged=typemax(Int),
                kwargs...)
    K == 4 && @test sol.retcode == :Success
    K == 3 && @test_broken sol.retcode == :Success
    # FIXME: maybe I'll need some `MaxIters <: Message` to send this information
    # through the pipeline and only check for `MaxIters` or `Convergence` after
    # the last stage.
    lastiters = [s.k-1 for s in sol.stages]
    @test lastiters == [1, 2, 3]

    Uᵏ⁻¹ = [s.Uᵏ⁻¹ for s in sol.stages]
    @test Uᵏ⁻¹[1] == Counters(1, 0) # U₁¹ = F(U₀)
    @test Uᵏ⁻¹[2] == Counters(2, 0) # U₂² = F(F(U₀))
    @test Uᵏ⁻¹[3] == Counters(3, 0) # U₃³ = F(F(F(U₀)))
end

@testset "K=2 (insufficient)" begin
    sol = solve(counting_prob, counting_alg;
                maxiters=2,
                # disable convergence checks; don't evaluate norm(::Counters)
                nconverged=typemax(Int),
                kwargs...)
    @test sol.retcode == :MaxIters
    lastiters = [s.k-1 for s in sol.stages]
    @test lastiters == [1, 2, 2]

    Uᵏ⁻¹ = [s.Uᵏ⁻¹ for s in sol.stages]
    @test Uᵏ⁻¹[1] == Counters(1, 0) # U₁¹ = F(U₀)
    @test Uᵏ⁻¹[2] == Counters(2, 0) # U₂² = F(F(U₀))
    @test Uᵏ⁻¹[3] == Counters(7, 10) # U₃²
    # U₃² = G(F(F(U₀))) + F(U₂¹) - G(U₂¹), i.e. #F=3+2+2, #G=2+4+4
    # U₂¹ = G(F(U₀)) + F(G(U₀)) - G(G(U₀)), i.e. #F=2, #G=4
end

struct TallyCounter
    n::Int
end

ParaReal.value(s::TallyCounter) = s.n

inc_until_2 = p -> p.v < 1 ? TallyCounter(p.v+1) : TallyCounter(p.v)
converge_prob = ParaReal.Problem(TestProblem(0))
converge_after_2 = ParaReal.Algorithm(inc_until_2, inc_until_2)

@testset "Early Convergence" begin
    # Use sufficient K, that must not be reached:
    sol = solve(converge_prob, converge_after_2; maxiters=3, kwargs...)
    @test sol.retcode == :Success
    lastiters = [s.k-1 for s in sol.stages]
    @test lastiters == [1, 2, 2]
end
