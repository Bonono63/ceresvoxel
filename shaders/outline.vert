#version 450

layout(push_constant, std430) uniform push_constants {
    layout(offset=0) mat4 view_proj;
    layout(offset=64) float aspect_ratio;
    layout(offset=64+4) uint draw_index;
} pc;

struct Data {
    mat4 model;
    vec4 color;
} data;

layout(binding = 0) readonly uniform block_selection_transform {
    Data u[10000];
} bst;

layout(location = 0) in vec3 in_pos;

layout(location = 0) out vec4 fragColor;

void main()
{
    const int ubo_index = gl_InstanceIndex;
    gl_Position = pc.view_proj * bst.u[ubo_index].model * vec4(in_pos, 1.0);
    fragColor = bst.u[ubo_index].color;
}
