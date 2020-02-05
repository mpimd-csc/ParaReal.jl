using Test, Distributed
using ParaReal
using ParaReal: local_tspan

nprocs() == 1 && addprocs(10)

@everywhere begin
    @info "Loading modules on process $(myid())"
    using ParaReal, LinearAlgebra, DifferentialEquations
end

verbose = isinteractive()

