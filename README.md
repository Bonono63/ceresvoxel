# CeresVoxel
A Voxel Engine

Technical details:
The engine is written in the Zig programming language, utilizes the Vulkan graphics API, and GLFW for interfacing with the Operating System.
It is intended to have a relatively simple rendering system with modular renderers.

## Build:
Do not use the nix flake because the zig binary will not link against your host system's vulkan library.
I don't know how to fix this atm.
