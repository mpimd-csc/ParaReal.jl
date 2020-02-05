function local_tspan(step::Integer, n::Integer, tspan::Tuple{T,T}) where T <: Integer
    t0, tf = tspan
    t0′ = (n-step+1)*t0 + (step-1)*tf
    tf′ = (n-step)  *t0 + (step)  *tf
    t0′ ÷= n
    tf′ ÷= n
    t0′ == tf′ && error("Empty tspan for step $step out of $n")
    (t0′, tf′)
end

function local_tspan(step::Integer, n::Integer, tspan::Tuple{T,T}) where T
    t0, tf = tspan
    t0′ = (n-step+1)*t0 + (step-1)*tf
    tf′ = (n-step)  *t0 + (step)  *tf
    t0′ /= n
    tf′ /= n
    (t0′, tf′)
end
