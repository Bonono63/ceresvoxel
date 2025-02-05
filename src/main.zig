const std = @import("std");

const c = @import("clibs.zig");

const ENGINE_NAME = "CeresVoxel";

const VkAbstractionError = error{
    Success,
    GLFWInitialization,
    WindowReturnednull,
    TooManyExtensions,
    VkInstanceCreation,
    OutOfMemory,
};

const instance_extensions_size = 1;
const instance_extensions = [1][*c]const u8{
    "VK_KHR_DISPLAY",
};
//"VK_LAYER_KHRONOS_validation"

const device_extensions = [1][]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

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
    const window_success = window_setup(&instance);

    if (window_success != VkAbstractionError.Success) {
        std.debug.print("Unable to complete window setup\n", .{});
    } else {
        std.debug.print("Window Setup completed\n", .{});
    }
}

/// Initializes our vulkan instance and window instance through glfw
/// Returns nothing if there is no error?
pub fn window_setup(instance: *Instance) VkAbstractionError {
    if (c.glfwInit() != c.GLFW_TRUE) {
        return VkAbstractionError.GLFWInitialization;
    }

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

    const window: ?*c.GLFWwindow = c.glfwCreateWindow(600, 800, "Zig Vulkan Test", null, null);

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
    _ = c.glfwGetRequiredInstanceExtensions(&required_extension_count);
    const required_extensions = c.glfwGetRequiredInstanceExtensions(&required_extension_count);

    std.debug.print("required extensions size: {}\n", .{required_extension_count});
    std.debug.print("required extensions type: {}\n", .{@TypeOf(required_extensions)});

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    const Allocator = arena.allocator();
    var extensions_arraylist = std.ArrayList([*c]const u8).init(Allocator);
    defer extensions_arraylist.deinit();

    //std.debug.print("test_arraylist size: {}\n", .{test_arraylist.size});
    //test_arraylist.appendSlice(test_arraylist, required_extensions);
    for (0..required_extension_count) |i| {
        try extensions_arraylist.append(required_extensions[i]);
    }

    for (0..instance_extensions_size) |i| {
        try extensions_arraylist.append(instance_extensions[i]);
    }

    std.debug.print("Required Extensions: \n", .{});
    for (0..required_extension_count) |i| {
        std.debug.print("\t{s}\n", .{required_extensions[i]});
    }

    std.debug.print("ArrayList contents\n", .{});
    for (extensions_arraylist.items) |item| {
        std.debug.print("\t{s}\n", .{item});
    }

    // We want to make sure our conversion from u32 to usize is safe
    if (extensions_arraylist.items.len > std.math.maxInt(u32)) {
        return VkAbstractionError.TooManyExtensions;
    }

    std.debug.print("extensions arraylist cast type: {}\n", .{@TypeOf(@as([*c][*c]const u8, extensions_arraylist.items))});

    const create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &application_info,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = undefined,
        .enabledExtensionCount = @intCast(extensions_arraylist.items.len),
        .ppEnabledExtensionNames = @ptrCast(extensions_arraylist.items),
    };

    const instance_result = c.vkCreateInstance(&create_info, null, &instance.vk_instance);

    if (instance_result != c.VK_SUCCESS) {
        std.debug.print("Unable to make Vk Instance\n", .{});
        return VkAbstractionError.VkInstanceCreation;
    }

    return VkAbstractionError.Success;
}
