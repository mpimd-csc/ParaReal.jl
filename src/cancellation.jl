struct CancelCtx
    done::RemoteChannel{Channel{Nothing}}
    CancelCtx() = new(RemoteChannel(() -> Channel{Nothing}(0)))
end

iscanceled(ctx::CancelCtx) = !isopen(ctx.done)
cancel!(ctx::CancelCtx) = (close(ctx.done); nothing)
