using Documenter, ParaReal
using Literate

# Generate examples
EXAMPLES = joinpath(@__DIR__, "..", "demo")
OUTPUT = joinpath(@__DIR__, "src", "generated", "demo")
for f in ("counting.jl", "riccati.jl")
    example = joinpath(EXAMPLES, f)
    Literate.markdown(example, OUTPUT,
        execute=false,
        codefence="````julia" => "````", # disable execution by Documenter
    )
end

# Generate documentation
makedocs(
    format = Documenter.HTML(
        edit_link=nothing,
    ),
    sitename = "ParaReal.jl",
    modules = [ParaReal],
    pages = [
        "Home" => "index.md",
        "Demos" => [
            "generated/demo/counting.md",
            "generated/demo/riccati.md",
        ],
        "logging.md",
        "api.md",
    ],
)
