pub usingnamespace @cImport({
    @cInclude("stdlib.h");
    //@cDefine("VMA_STATIC_VULKAN_FUNCTIONS", .{0,});
    //@cDefine("VMA_DYNAMIC_VULKAN_FUNCTIONS", .{1,});
    //@cDefine("VMA_IMPLEMENTATION", {});
    @cInclude("vk_mem_alloc.h");
    @cInclude("vulkan/vulkan.h");
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
    @cInclude("cglm/cglm.h");
});
