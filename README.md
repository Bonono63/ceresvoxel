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
    add staging buffer abstraction so we can do the transfer commands all in one command buffer.

## Compilation

VMA and stb_image are compiled seperately into a binary library that is then statically linked because
VMA uses cpp so it can not be included traditionally into the project and stb_image doesn't completely
respect pointer alignment and so the translated header results in compilation errors, both of which
can be avoided by side stepping the zig compilers checks...
