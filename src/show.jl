function Base.show(io::IO, pl::Pipeline{S}) where {S}
    N = length(pl.stages)
    println(io, "Pipeline{$S} with $N stages:")
    for (n, r) in enumerate(pl.stages)
        l, k, failed, cancelled, converged = fetch_from_owner(r) do s::Stage
            s.loc, s.k, isfailed(s), iscancelled(s), s.converged
        end
        desc = if k == 0
            "not yet started"
        elseif failed
            "failed"
        elseif cancelled
            "cancelled"
        elseif converged
            "converged"
        else
            "ok"
        end
        println(io, " stage $n located at $l: $desc")
    end
end

function Base.show(io::IO, s::Stage)
    fields = (:n, :k, :loc, :cancelled, :converged, :nconverged, :queue, :ex)
    print(io, "Stage")
    for f in fields
        v = getfield(s, f)
        print(io, "\n $f: ", v)
    end
    if s.st !== nothing
        st = s.st
        print(io, "\n st: ", st[1])
        for i in 2:min(length(st), 20)
            print(io, "\n     ", st[i])
        end
    end
end
