# Matrix Riccati Equation

Consider the Differential Riccati Equation (DRE)

```math
\left\{
\begin{aligned}
E^T \dot X E &= -\big( C^T C + A^T X E + E^T X A - E^T X BB^T X E \big)
\\
E^T X(t_f) E &= \tfrac{1}{100} C^T C
\end{aligned}
\right.
```

for autonomous system matrices $E,A,B,C$.
In general, the solution $X(t) \in\mathbb R^{n\times n}$ is dense but has a low numerical rank.[^Lang2017]
For a large state dimension it is therefore infeasible to store $X$ as a `Matrix`.
We will use [`DifferentialRiccatiEquations`](https://gitlab.mpi-magdeburg.mpg.de/jschulze/DifferentialRiccatiEquations.jl)
and its `LDLᵀ` data type that represents every solution value as

```math
X(t) = LDL^T
```

where $L\in\mathbb R^{n\times r}$ is a skinny matrix, i.e. $r \ll n$.

[^Lang2017]: See e.g. Section 2.1.4 and the references therein: Norman Lang. "Numerical methods for large-scale linear time-varying control systems and related differential matrix equations." PhD thesis. Technische Universität Chemnitz, 2017.

# Implement Problem Interface

Define methods for

```
initial_value(::SomeProblem)
remake_prob(::SomeProblem, value, tspan)
```
