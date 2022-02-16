# DEV

# v0.4.0

- More robust convergence criterion: convergence is reached after `nconverged`
  successive Newton refinements without significant change, and the number of
  refinements differs by at most 1 from stage to stage.
- Rename `initialvalue` to `initial_value`.
- Rename `nextvalue` to `value`.
- Simplified design around `Problem` as well as `Algorithm`: they are now simple
  wrappers (i.e. `struct`s) of user-defined problem instance as well as solver
  and update functions, respectively (instead of being `abstract type`s).
  To support their own types, users need to define methods for `remake_prob`,
  `initial_value`, and `value`.
- Rename `Waiting` event (start/stop) to `WaitingRecv`.
- Add new `WaitingSend` and `CheckConv` events (start/stop).
- Require Julia v1.6.

# v0.3.0

- Fix deadlock due to fake convergence (!26)
- Use default logging frontend (`@info` and friends) for event creation (#27)

# v0.2.1

- Add keyword arguments `warmupc`, `warmupf` to control JIT warm-up (!25)

# v0.2

- Don't send individual solutions back to the managing process (by default at least)
- Add event log to the global solution object
- Refactor `Pipeline` interface (compatible to `CommonSolve`): `init`, `solve!`, `cancel_pipeline!`

# v0.1

- Start naming things
