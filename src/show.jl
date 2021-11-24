function Base.show(io::IO, pl::Pipeline)
    n = length(pl.workers)
    println(io, "Pipeline with $n stages:")
    for i in 1:n
        w = pl.workers[i]
        s = if pl.tasks !== nothing
            pl.tasks[i]
        else
            "not yet started"
        end
        println(io, " stage $i on worker $w: $s")
    end
end
