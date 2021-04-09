function Base.show(io::IO, pl::Pipeline)
    n = length(pl.workers)
    println(io, "Pipeline with $n stages:")
    for (i, w, s) in zip(1:n, pl.workers, pl.status)
        println(io, " stage $i on worker $w: $s")
    end
end
