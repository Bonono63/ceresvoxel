#version 450

layout(push_constant, std430) uniform push_constants {
    layout(offset=0) mat4 view_proj;
    layout(offset=64) uint block_selection_index;
    layout(offset=68) float aspect_ratio;
    layout(offset=72) uint chunk_pos;
} pc;

layout(binding = 0) uniform object_transform {
    mat4 model;
    uint pos[1024];
} ubo;

layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec3 in_color;

layout(location = 0) out vec3 fragColor;

void main()
{
    gl_Position = vec4(in_pos.x, in_pos.y * pc.aspect_ratio, in_pos.z, 1.0);
    fragColor = in_color;
}
