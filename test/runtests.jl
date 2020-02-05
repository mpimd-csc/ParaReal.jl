include("setup.jl")

@time @testset "ParaReal.jl" begin
    include("utils.jl")
    include("simple.jl")
end

