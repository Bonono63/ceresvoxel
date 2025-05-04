#version 450

layout(binding = 1) uniform sampler2D tex_sampler;

layout(location = 0) out vec4 outColor;
layout(location = 0) in vec3 fragColor;

void main()
{
    outColor = texture(tex_sampler, fragColor.xy);
}
