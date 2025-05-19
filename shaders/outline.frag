#version 450

//layout(binding = 2) uniform sampler2D tex_sampler;

layout(location = 0) out vec4 outColor;
layout(location = 0) in vec3 fragColor;

void main()
{
    outColor = vec4(fragColor, 1.0);//texture(tex_sampler, fragColor.xy);
}
