#version 450

layout(push_constant, std430) uniform push_constants {
    layout(offset=0) mat4 view_proj;
    layout(offset=64) uint block_selection_index;
} pc;

layout(binding = 0) uniform object_transform {
    mat4 model;
    mat4 view;
    mat4 projection;
} ubo;

layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec3 in_color;

layout(location = 0) out vec3 fragColor;

void main()
{
    const vec3 chunk_pos = {in_color[2],0.0,0.0};
    gl_Position = pc.view_proj * ubo.model * vec4(in_pos + chunk_pos, 1.0);
    fragColor = in_color;
}
