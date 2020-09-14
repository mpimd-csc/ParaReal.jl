include("setup.jl")

@time @testset "ParaReal.jl" begin
    include("utils.jl")
    @testset "simple (Bargo2009)" begin include("simple.jl") end
    @testset "non-diffeq" begin include("non-diffeq.jl") end
end

