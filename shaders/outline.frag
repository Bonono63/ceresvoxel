#version 450

//layout(binding = 2) uniform sampler2D tex_sampler;

layout(location = 0) out vec4 outColor;
layout(location = 0) in vec4 fragColor;

void main()
{
    outColor = fragColor;//texture(tex_sampler, fragColor.xy);
}
