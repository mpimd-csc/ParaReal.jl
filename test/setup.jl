using Test, Distributed
using ParaReal

nprocs() == 1 && addprocs(10)

@everywhere begin
    @info "Loading modules on workers"
    using ParaReal, LinearAlgebra, DifferentialEquations
end

# Override this in a shell before including single test scripts:
verbose = false

