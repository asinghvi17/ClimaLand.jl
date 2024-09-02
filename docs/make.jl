using Documenter, DocumenterVitepress

using ClimaLand

makedocs(;
    modules=[ClimaLand],
    authors="ClimaLand team",
    repo="https://github.com/CliMA/ClimaLand.jl",
    sitename="ClimaLand.jl",
    format=DocumenterVitepress.MarkdownVitepress(
        repo = "https://github.com/CliMA/ClimaLand.jl",
        devurl = "dev",
        deploy_url = "CliMA.github.io/ClimaLand.jl",
    ),
    pages=[
        "Home" => "index.md",
        "Getting started" => "getting_started.md",
        "API" => "API.md",
    ],
    warnonly = true,
)

deploydocs(;
    repo="github.com/CliMA/ClimaLand.jl",
    push_preview=true,
)
