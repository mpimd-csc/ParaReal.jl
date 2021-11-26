using Distributed, Base.Threads, Test
using ParaReal

verbose = isinteractive()

const D = Distributed
const T = Threads
const PR = ParaReal

_prepare(eventlog, n) = [e.tag for e in eventlog if e.n == n]

@time @testset "ParaReal.jl" begin
    include("utils.jl")
    @testset "Explosions" begin include("explosions.jl") end
    @testset "Pipeline Interface" begin include("pipeline.jl") end
    @testset "Logging" begin include("logging.jl") end
    @testset "Problem Types" begin
        @testset "diffeq ODE" begin
            include("problems/diffeq-ode.jl")
            include("problems/diffeq-ode2.jl")
        end
        @testset "non-diffeq" begin include("problems/non-diffeq.jl") end
    end
end

