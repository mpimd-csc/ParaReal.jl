include("setup.jl")

@time @testset "ParaReal.jl" begin
    include("simple.jl")
end

