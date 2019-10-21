# Props to tkf: https://github.com/JuliaLang/julia/pull/33555

import Base: iterate, IteratorSize

function Base.iterate(c::RemoteChannel, state=nothing)
    try
        return (take!(c), nothing)
    catch e
        if isa(e, InvalidStateException) && e.state == :closed
            return nothing
        else
            rethrow()
        end
    end
end

Base.IteratorSize(::Type{<:RemoteChannel}) = Base.SizeUnknown()
