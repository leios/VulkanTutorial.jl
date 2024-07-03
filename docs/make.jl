using Documenter

makedocs(
    sitename="Vulkan Tutorial",
    authors="James Schloss (Leios)",
    pages = [
        "General Information" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/leios/VulkanTutorial.jl",
    versions = nothing,
)
