#version 450

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
    //gl_Position = ubo.projection * ubo.view * ubo.model * vec4(in_pos, 0.0, 1.0);
    gl_Position = ubo.projection * ubo.view * ubo.model * vec4(in_pos, 1.0);
    fragColor = in_color;
}
