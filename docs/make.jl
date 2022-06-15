using Documenter, ParaReal

makedocs(
    sitename = "ParaReal.jl",
    modules = [ParaReal],
    pages = [
        "Home" => "index.md",
        "Demos" => [
            "demo/counting.md",
            "demo/riccati.md",
        ],
        "logging.md",
        "api.md",
    ],
)
