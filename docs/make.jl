using Documenter, ParaReal

makedocs(
    sitename = "My Doc",
    modules = [ParaReal],
    pages = [
        "index.md",
        "Demos" => [
            "demo/counting.md",
            "demo/riccati.md",
        ],
        "logging.md",
        "api.md",
    ],
)
