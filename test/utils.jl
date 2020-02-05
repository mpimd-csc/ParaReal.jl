@testset "local_tspan" begin
    @testset "Covering the original interval" begin
        n = 4
        tspan = (0., 10.)
        tspans = map(step -> local_tspan(step, n, tspan), 1:n)
        @test first(tspans)[1] === tspan[1]
        @test last(tspans)[2] === tspan[2]
        for i = 1:n-1
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
