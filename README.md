# CeresVoxel
A Voxel Engine

TODO:

    HIGH PRIORITY:
    Finish Iterative physics solver (Maybe Jacobian later???)
    XPBD physics solver?
    Prune and Sweep algorithm
    RK4 Integration
    Localized physics (planet faces are simplified into planes)
    Make the collision detection and resolution completely precision agnostic from position
    Procedural world generation
    Chunk LOD system
    Chunk culling algorithm
    block editing (placing and destroying)
    UI system
    HP and Hunger system
    early game

    LOW PRIORITY:
    Free cam mode toggle (c key)

Technical details:

zmath is used for math,
glfw for window events and input,
vulkan for graphics,
AMD's vma is used for device memory allocation,

## Compilation

run ``zig build --release=fast`` in the root directory of the project to build the release executable.

VMA and stb_image are compiled seperately into a binary library that is then statically linked because
VMA uses cpp so it can not be included traditionally into the project and stb_image doesn't completely
respect pointer alignment and so the translated header results in compilation errors, both of which
can be avoided by side stepping the zig compilers checks...
