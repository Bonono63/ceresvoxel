# CeresVoxel
A Voxel Engine

Technical details:
The engine is written in the Zig programming language, utilizes the Vulkan graphics API, and GLFW for interfacing with the Operating System.

zmath is used for math,
glfw for window events and input,
vulkan for graphics,
AMD's vma is used for device memory allocation,

TODO:

    Use a staging buffer for vertex data
    Fix resizing error reported by validation layer
    Fix Nvidia proprietary driver leak during render runtime
    Move Renderer to a seperate thread and have gameplay run seperately from logic

## Compilation

