using Distributed, Base.Threads, Test

verbose = isinteractive()
nprocs() == 1 && addprocs(10)
@everywhere using ParaReal

const D = Distributed
const T = Threads
const PR = ParaReal

@time @testset "ParaReal.jl" begin
    include("utils.jl")
    @testset "Pipeline Interface" begin include("pipeline.jl") end
    @testset "simple (Bargo2009)" begin include("simple.jl") end
    @testset "non-diffeq" begin include("non-diffeq.jl") end
end

