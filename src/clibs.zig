//!Imported C libraries
pub const c = @cImport({
    @cInclude("stdlib.h");
});

pub const vulkan = @cImport({
    @cInclude("vk_mem_alloc.h");
    @cInclude("vulkan/vulkan.h");
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
});

pub const stb = @cImport({
    @cInclude("stb_image.h");
});
