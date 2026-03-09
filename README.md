# CeresVoxel
A Voxel Engine

TODO:

    HIGH PRIORITY:
    Finish Iterative physics solver
    Make physics relative: Make the collision detection and resolution completely precision agnostic from position
    Localized physics: each planet should have its own physics world like Super Mario Galaxy. Different worlds can be thrown into different threads to improve parallelism. This should also improve stability since math for entities on a planet's surface can be simplified to the faces of a non-moving cube.
    Procedural world/biome generation
    block editing (placing and destroying)
    UI system
    HP and Hunger system
    early game

    LOW PRIORITY:
    Free cam mode toggle (c key)
    Prune and Sweep algorithm
    RK4 Integration
    XPBD physics solver?
    Chunk culling algorithm
    Chunk LOD system (goal is to make it so we can see full planets regardless of distance even if they are simplified to just a textured cube)
    More accurate orbital mechanics for planets
    Material system for physics that provide restitution

## Compilation

run ``zig build --release=fast`` in the root directory of the project to build the release executable.
