#version 450

layout(push_constant, std430) uniform push_constants {
    layout(offset=0) mat4 view_proj;
    layout(offset=64) uint block_selection_index;
    layout(offset=128) float aspect_ratio;
} pc;

layout(binding = 0) uniform chunk_transform {
    mat4 model;
} ct;

struct chunk {
    uint x;
    uint y;
    uint z;
    mat4 model;
};

layout(binding = 3) readonly buffer chunk_data {
    chunk data[];
} cd;

layout(location = 0) in uint chunk_index;
layout(location = 1) in vec2 uv;
layout(location = 2) in uint in_pos;

layout(location = 0) out vec2 uv_out;

void main()
{
    const float x = in_pos % 32 + cd.data[chunk_index].x;
    const float y = in_pos / 32 % 32 + cd.data[chunk_index].y;
    const float z = in_pos / 32 / 32 % 32 + cd.data[chunk_index].z;
    gl_Position = pc.view_proj * vec4(x, y, z, 1.0);
    uv_out = uv;
}
