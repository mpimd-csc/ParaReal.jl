"""
Van der Pol oscillator
"""
function vanderpol!(du, u, p, t)
    du[1] = u[2]
    du[2] = (1-u[1]^2) * u[2] - u[1]
    nothing
end

"""
Arenstorf orbit
"""
function arenstorf!(du, u, p, t)
    x, y, dx, dy = u
    μ = p

    μ_hat = 1 - μ
    N1 = sqrt((x + μ)^2     + y^2)^3
    N2 = sqrt((x - μ_hat)^2 + y^2)^3

    du[1] = dx
    du[2] = dy
    du[3] = x + 2dy - μ_hat*(x + μ)/N1 - μ*(x - μ_hat)/N2;
    du[4] = y - 2dx - μ_hat*y/N1       - μ*y/N2;
    nothing
end
