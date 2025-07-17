#version 450

layout(push_constant, std430) uniform push_constants {
    layout(offset=0) mat4 view_proj;
    layout(offset=64) float aspect_ratio;
} pc;

layout(binding = 0) uniform chunk_transform {
    mat4 model;
} ct;

struct chunk {
    uint size_x;
    uint size_y;
    uint size_z;
    vec3 pos;
    mat4 model;
};

layout(binding = 3) readonly buffer chunk_data {
    chunk data[];
} cd;

layout(location = 0) in uint chunk_index;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec3 in_pos;

layout(location = 0) out vec2 uv_out;

void main()
{
    gl_Position = pc.view_proj * cd.data[chunk_index].model * vec4(in_pos + cd.data[chunk_index].pos, 1.0);
    //gl_Position = pc.view_proj * vec4(in_pos, 1.0);
    uv_out = uv;
}
