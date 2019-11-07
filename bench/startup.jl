cd(@__DIR__) do
    @info "First run"
    include("simple.jl")
    t1 = t
    @info "Second run"
    include("simple.jl")
    t2 = t

    println("first,  ", join(t1, ", "))
    println("second, ", join(t2, ", "))
end
