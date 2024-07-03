# VulkanTutorial.jl
This is Vulkan tutorial writtin in "idiomatic" Julia

Here are the goals for this project:
1. Implement the vulkan tutorial (.com) in Julia
2. Consider key abstractions necessary to translate Julia shaders to GLSL / SpirV (ShaderAbstractions). Then use those abstractions here.
3. Check performance between:
    1. KernelAbstractions and ShaderAbstractions for Compute with an NBody example
    2. Vulkan C (with someone else's Vulkan C tutorial code)
