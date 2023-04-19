# This file is a part of ParaReal. License is MIT: https://spdx.org/licenses/MIT.html

# run, t_load, t_solve
@info "First run"
print("1, ")
include("startup-single.jl")
@info "Second run"
print("2, ")
include("startup-single.jl")
