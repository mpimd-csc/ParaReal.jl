using Distributed, Base.Threads, Test
using ParaReal

verbose = isinteractive()

const D = Distributed
const T = Threads
const PR = ParaReal

@time @testset "ParaReal.jl" begin
    include("utils.jl")
    @testset "Pipeline Interface" begin include("pipeline.jl") end
    @testset "Problem Types" begin
        @testset "diffeq ODE" begin include("problems/diffeq-ode.jl") end
        @testset "non-diffeq" begin include("problems/non-diffeq.jl") end
    end
end

