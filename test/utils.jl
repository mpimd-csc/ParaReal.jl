using ParaReal: local_tspan, init_pipeline
using Test

@testset "local_tspan" begin
    @testset "Covering the original interval" begin
        N = 4
        tspan = (0., 10.)
        tspans = map(n -> local_tspan(n, N, tspan), 1:N)
        @test first(tspans)[1] === tspan[1]
        @test last(tspans)[2] === tspan[2]
        for i = 1:N-1
            @test tspans[i][2] === tspans[i+1][1]
        end
    end
    @testset "Type compatibility" begin
        @test local_tspan(3, 5, (0., 10.)) === (4.0, 6.0)
        @test local_tspan(3, 5, (0, 10)) === (4, 6)
        @test local_tspan(2, 5, (0., 1.)) === (0.2, 0.4)
        @test_throws ErrorException local_tspan(2, 5, (0,1))
    end
end

@testset "Pretty Printing" begin
    pl = init_pipeline([1, 1, 1])
    str = repr("text/plain", pl)
    expected = """
    Pipeline with 3 stages:
     stage 1 on worker 1: Initialized
     stage 2 on worker 1: Initialized
     stage 3 on worker 1: Initialized
    """
    @test str == expected
end
