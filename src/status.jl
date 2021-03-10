isdone(s::Symbol) = s in (:Done, :Cancelled, :Failed)

iscancelled(s::Symbol) = s == :Cancelled

isfailed(s::Symbol) = s == :Failed
