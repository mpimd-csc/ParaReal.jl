using Test, Distributed
using ParaReal

nprocs() == 1 && addprocs(10)

@everywhere begin
    @info "Loading modules on process $(myid())"
    using ParaReal, LinearAlgebra, DifferentialEquations
end

verbose = isinteractive()

