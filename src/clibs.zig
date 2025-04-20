pub usingnamespace @cImport({
    @cInclude("stdlib.h");
    @cInclude("vk_mem_alloc.h");
    @cInclude("vulkan/vulkan.h");
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
    @cInclude("cglm/cglm.h");
});
