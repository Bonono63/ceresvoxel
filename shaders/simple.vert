#version 450

layout(push_constant, std430) uniform push_constants {
    layout(offset=0) mat4 view_proj;
    layout(offset=64) uint block_selection_index;
    layout(offset=64+4) float aspect_ratio;
    layout(offset=64+4+4) uint chunk_index;
} pc;

layout(binding = 0) uniform chunk_transform {
    mat4 model;
    uint pos[1024];
} ct;

layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec3 in_color;

layout(location = 0) out vec3 fragColor;

void main()
{
    const uint posx = ct.pos[pc.chunk_index] >> 24;
    const uint posy = ct.pos[pc.chunk_index] >> 16 & 0xFF;
    const uint posz = ct.pos[pc.chunk_index] >> 8 & 0xFF;
    const vec3 chunk_pos = {posx * 32.0, posx * 32.0, posz * 32.0};
    gl_Position = pc.view_proj * ct.model * vec4(in_pos + chunk_pos, 1.0);
    fragColor = in_color;
}
