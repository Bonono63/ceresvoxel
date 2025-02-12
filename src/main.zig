//Proceeds to zig all over the place...
const std = @import("std");

const c = @import("clibs.zig");

const ENGINE_NAME = "CeresVoxel";

const VkAbstractionError = error{
    Success,
    GLFWInitialization,
    WindowReturnednull,
    TooManyExtensions,
    VkInstanceCreation,
    UnableToCreateSurface,
    VulkanUnavailable,
    OutOfMemory,
};

const instance_extensions = [_][*:0]const u8{
    "VK_KHR_display",
};

const validation_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const device_extensions = [_][*:0]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

// Is it a compiler quirk that tuples with default values have to be at the end of the struct?
const Instance = struct {
    // I hate to initialize these all to NULL, but it is what it is with c compat...
    vk_instance: c.VkInstance = null,
    window: ?*c.GLFWwindow = null,
    surface: c.VkSurfaceKHR = null,
    physical_device: c.VkPhysicalDevice = null,
    device: c.VkDevice = null,
    graphics_queue: ?*c.VkQueue = null,
    swapchain: c.VkSwapchainKHR = undefined,
    swapchain_format: c.VkSurfaceFormatKHR = undefined,
    swapchain_image_count: u32 = 0,
    swapchain_images: ?*c.VkImage = null,
    swapchain_image_views: ?*c.VkImageView = null,
    swapchain_extent: c.VkExtent2D = undefined,

    const REQUIRE_FAMILIES: u32 = c.VK_QUEUE_GRAPHICS_BIT;
};

pub fn main() !void {
    var instance: Instance = .{};

    const glfw_success = glfw_initialization();

    if (glfw_success != VkAbstractionError.Success) {
        std.debug.print("Unable to initialize GLFW\n", .{});
        return;
    }

    const window_success = window_setup(&instance);

    if (window_success != VkAbstractionError.Success) {
        std.debug.print("Unable to complete window setup\n", .{});
        std.debug.print("Error code: {}\n", .{window_success});
    } else {
        std.debug.print("Window Setup completed\n", .{});
    }

    const surface_success = create_surface(&instance);

    if (surface_success != VkAbstractionError.Success) {
        std.debug.print("Unable to create window surface.\n", .{});
    }

    const clean_up_success = instance_clean_up(&instance);
    _ = &clean_up_success;
}

pub fn glfw_initialization() VkAbstractionError {
    if (c.glfwInit() != c.GLFW_TRUE) {
        return VkAbstractionError.GLFWInitialization;
    }

    const vulkan_supported = c.glfwVulkanSupported();
    if (vulkan_supported == c.GLFW_TRUE) {
        std.debug.print("Vulkan support is enabled\n", .{});
    } else {
        std.debug.print("Vulkan is not supported\n", .{});
        return VkAbstractionError.VulkanUnavailable;
    }

    const glfw_set_callback_error_success = c.glfwSetErrorCallback(glfw_error_callback);
    _ = &glfw_set_callback_error_success;
    //    if (glfw_set_callback_error_success != c.GLFW_TRUE) {
    //        std.debug.print("Unable to set GLFW error callback\n", .{});
    //    }

    return VkAbstractionError.Success;
}

pub fn glfw_error_callback(code: c_int, description: [*c]const u8) callconv(.C) void {
    std.debug.print("[Error] [GLFW] {} {s}\n", .{ code, description });
}

/// Initializes our vulkan instance and window instance through glfw
pub fn window_setup(instance: *Instance) VkAbstractionError {
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

    // Window must be accessable outside of the function scope so no defer...
    const window: ?*c.GLFWwindow = c.glfwCreateWindow(600, 800, ENGINE_NAME, null, null);

    if (window == null) {
        c.glfwTerminate();
        return VkAbstractionError.WindowReturnednull;
    }

    instance.window = window;

    const application_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = ENGINE_NAME,
        .pEngineName = ENGINE_NAME,
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_3,
    };

    std.debug.print("Vulkan Application Info:\n", .{});
    std.debug.print("\tVulkan application name: {s}\n", .{application_info.pApplicationName});
    std.debug.print("\tVulkan Engine name: {s}\n", .{application_info.pEngineName});

    var required_extension_count: u32 = 0;
    const required_extensions = c.glfwGetRequiredInstanceExtensions(&required_extension_count);

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    const Allocator = arena.allocator();
    var extensions_arraylist = std.ArrayList([*:0]const u8).init(Allocator);
    defer extensions_arraylist.deinit();

    for (0..required_extension_count) |i| {
        try extensions_arraylist.append(required_extensions[i]);
    }

    for (0..instance_extensions.len) |i| {
        try extensions_arraylist.append(instance_extensions[i]);
    }

    std.debug.print("Vulkan Instance Extensions:\n", .{});
    for (extensions_arraylist.items) |item| {
        std.debug.print("\t{s}\n", .{item});
    }

    // We want to make sure our conversion from u32 to usize is safe, this is a cast from u64 to u32
    if (extensions_arraylist.items.len > std.math.maxInt(u32)) {
        return VkAbstractionError.TooManyExtensions;
    }

    const create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &application_info,
        .enabledLayerCount = @intCast(validation_layers.len),
        .ppEnabledLayerNames = &validation_layers,
        .enabledExtensionCount = @intCast(extensions_arraylist.items.len),
        .ppEnabledExtensionNames = extensions_arraylist.items.ptr,
    };

    const instance_result = c.vkCreateInstance(&create_info, null, &instance.vk_instance);

    if (instance_result != c.VK_SUCCESS) {
        std.debug.print("Unable to make Vk Instance: {}\n", .{instance_result});
        return VkAbstractionError.VkInstanceCreation;
    }

    return VkAbstractionError.Success;
}

pub fn create_surface(instance: *Instance) VkAbstractionError {
    var surface: c.VkSurfaceKHR = undefined;

    const success = c.glfwCreateWindowSurface(instance.vk_instance, instance.window, null, &surface);

    if (success != c.VK_SUCCESS) {
        std.debug.print("Error code: {}\n", .{success});
        return VkAbstractionError.UnableToCreateSurface;
    } else {
        return VkAbstractionError.Success;
    }
}

pub fn instance_clean_up(instance: *Instance) !void {
    c.glfwDestroyWindow(instance.window);
}
