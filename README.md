# CeresVoxel



TODO:

    HIGH PRIORITY:
    Procedural world/biome generation
    block editing (placing and destroying)
    UI system
    HP and Hunger system
    early game

    LOW PRIORITY:
    change maximum rendered chunks (UBO) in GPU pipeline
    Chunk culling algorithm
    Chunk LOD system (goal is to make it so we can see full planets regardless of distance even if they are simplified to just a textured cube)
    More accurate orbital mechanics for planets
    drag and heat from orbital re-entrance
    contact explosions based on velocity
    player damage based on objects hitting them
    Material system for physics that provide restitution

## Compilation

Using zig 0.15.x run ``zig build --release=fast`` in the root directory of the project to build the release executable.
