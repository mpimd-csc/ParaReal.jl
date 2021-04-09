function local_tspan(n::Integer, N::Integer, tspan::Tuple{T,T}) where T <: Integer
    t0, tf = tspan
    t0′ = (N-n+1)*t0 + (n-1)*tf
    tf′ = (N-n)  *t0 + (n)  *tf
    t0′ ÷= N
    tf′ ÷= N
    t0′ == tf′ && error("Empty tspan for stage $n out of $N")
    (t0′, tf′)
end

function local_tspan(n::Integer, N::Integer, tspan::Tuple{T,T}) where T
    t0, tf = tspan
    t0′ = (N-n+1)*t0 + (n-1)*tf
    tf′ = (N-n)  *t0 + (n)  *tf
    t0′ /= N
    tf′ /= N
    (t0′, tf′)
end
