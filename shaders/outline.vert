#version 450

layout(push_constant, std430) uniform push_constants {
    layout(offset=0) mat4 view_proj;
    layout(offset=64) uint block_selection_index;
    layout(offset=68) float aspect_ratio;
    layout(offset=72) uint chunk_index;
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
    //gl_Position = ubo.projection * ubo.view * ubo.model * vec4(in_pos, 0.0, 1.0);
    const vec3 pos = vec3(
            in_pos.x + pc.block_selection_index % 32,
            in_pos.y + (pc.block_selection_index / 32 % 32),
            in_pos.z + pc.block_selection_index / 32 / 32 % 32
            );
    gl_Position = pc.view_proj * ct.model * vec4(pos, 1.0);
    fragColor = in_color;
}
