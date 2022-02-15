function fetch_from_owner(f, rr::Distributed.AbstractRemoteRef, args...)
    remotecall_fetch(rr.where, rr, args) do rrr, rargs
        @assert isready(rrr)
        f(fetch(rrr), rargs...)
    end
end

fetch_from_owner(f, sr::StageRef) = fetch_from_owner(f, getfield(sr, :c))

function Base.getproperty(sr::StageRef, p::Symbol)
    rr = getfield(sr, :c)
    fetch_from_owner(rr, p) do s::Stage, rp::Symbol
        getproperty(s, rp)
    end
end

Base.propertynames(::StageRef, private::Bool=false) = fieldnames(Stage)

Base.put!(sr::StageRef, s::Stage) = put!(getfield(sr, :c), s)
Base.fetch(sr::StageRef) = fetch(getfield(sr, :c))
# Base.take! is intentionally not implemented
