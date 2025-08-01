#version 450

layout(push_constant, std430) uniform push_constants {
    layout(offset=0) mat4 view_proj;
    layout(offset=64) float aspect_ratio;
} pc;

layout(binding = 0) uniform block_selection_transform {
    mat4 model;
} bst;

layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec3 in_color;

layout(location = 0) out vec3 fragColor;

void main()
{
    gl_Position = pc.view_proj * bst.model * vec4(in_pos, 1.0);
    fragColor = in_color;
}
