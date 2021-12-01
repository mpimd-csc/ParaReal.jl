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
