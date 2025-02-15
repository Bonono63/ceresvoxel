//Proceeds to zig all over the place...
const std = @import("std");

const c = @import("clibs.zig");

const ENGINE_NAME = "CeresVoxel";

const VkAbstractionError = error{
    Success,
    GLFWInitialization,
    GLFWErrorCallbackFailure,
    WindowReturnednull,
    TooManyExtensions,
    VkInstanceCreation,
    UnableToCreateSurface,
    VulkanUnavailable,
    InvalidDeviceCount,
    UnableToEnumeratePhysicalDevices,
    DeviceCreationFailure,
    UnableToRetrievePhysicalDeviceSurfaceCapabilities,
    UnableToRetrieveSurfaceFormat,
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
    window: *c.GLFWwindow = undefined,
    surface: c.VkSurfaceKHR = null,
    physical_device: c.VkPhysicalDevice = null,
    device: c.VkDevice = null,
    graphics_queue: c.VkQueue = undefined,
    swapchain: c.VkSwapchainKHR = undefined,
    swapchain_format: c.VkSurfaceFormatKHR = undefined,
    swapchain_image_count: u32 = 0,
    swapchain_images: *c.VkImage = undefined,
    swapchain_image_views: ?*c.VkImageView = null,
    swapchain_extent: c.VkExtent2D = undefined,
    REQUIRE_FAMILIES: u32 = c.VK_QUEUE_GRAPHICS_BIT,
};

const swapchain_support = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR = null,
    formats: *c.VkSurfaceFormatKHR = undefined,
    formats_size: u32 = 0,
    present_modes: *c.VkPresentModeKHR = undefined,
    present_size: u32 = 0,
};

pub fn main() !void {
    var instance: Instance = .{};

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    const allocator = arena.allocator();

    try glfw_initialization();

    try window_setup("Engine Test", &instance, &allocator);

    try create_surface(&instance);

    try pick_physical_device(&instance, &allocator);

    try create_graphics_queue(&instance, &allocator);

    instance_clean_up(&instance);
}

fn glfw_initialization() VkAbstractionError!void {
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

    _ = c.glfwSetErrorCallback(glfw_error_callback);
}

pub fn glfw_error_callback(code: c_int, description: [*c]const u8) callconv(.C) void {
    std.debug.print("[Error] [GLFW] {} {s}\n", .{ code, description });
}

/// Creates our vulkan instance and glfw window
fn window_setup(application_name: []const u8, instance: *Instance, allocator: *const std.mem.Allocator) VkAbstractionError!void {
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

    // zig is truly the goat
    instance.window = c.glfwCreateWindow(600, 800, ENGINE_NAME, null, null) orelse return VkAbstractionError.WindowReturnednull;

    const application_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = application_name.ptr,
        .pEngineName = ENGINE_NAME,
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_3,
    };

    std.debug.print("Vulkan Application Info:\n", .{});
    std.debug.print("\tVulkan application name: {s}\n", .{application_info.pApplicationName});
    std.debug.print("\tVulkan Engine name: {s}\n", .{application_info.pEngineName});

    var required_extension_count: u32 = 0;
    const required_extensions = c.glfwGetRequiredInstanceExtensions(&required_extension_count);

    var extensions_arraylist = std.ArrayList([*:0]const u8).init(allocator.*);
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
}

fn create_surface(instance: *Instance) VkAbstractionError!void {
    var surface: c.VkSurfaceKHR = undefined;

    const success = c.glfwCreateWindowSurface(instance.vk_instance, instance.window, null, &surface);

    if (success != c.VK_SUCCESS) {
        std.debug.print("Error code: {}\n", .{success});
        return VkAbstractionError.UnableToCreateSurface;
    }
}

fn pick_physical_device(instance: *Instance, allocator: *const std.mem.Allocator) VkAbstractionError!void {
    var device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(instance.vk_instance, &device_count, null);

    if (device_count <= 0) {
        return VkAbstractionError.InvalidDeviceCount;
    }

    const devices = try allocator.*.alloc(c.VkPhysicalDevice, device_count);
    defer allocator.*.free(devices);
    const enumerate_physical_device_success = c.vkEnumeratePhysicalDevices(instance.vk_instance, &device_count, devices.ptr);

    if (enumerate_physical_device_success != c.VK_SUCCESS) {
        return VkAbstractionError.UnableToEnumeratePhysicalDevices;
    }

    instance.physical_device = devices[0];

    var device_properties: c.VkPhysicalDeviceProperties = undefined;
    _ = c.vkGetPhysicalDeviceProperties(instance.physical_device, &device_properties);

    std.debug.print("API version: {any}\nDriver version: {any}\nDevice name: {s}\n", .{ device_properties.apiVersion, device_properties.driverVersion, device_properties.deviceName });

    // TODO Check for device extension compatibility
}

fn create_graphics_queue(instance: *Instance, allocator: *const std.mem.Allocator) VkAbstractionError!void {
    const flags = instance.REQUIRE_FAMILIES;
    const priority: f32 = 1.0;

    var queue_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceQueueFamilyProperties(instance.*.physical_device, &queue_count, null);
    std.debug.print("[Info] Queue count: {}\n", .{queue_count});

    const properties = try allocator.*.alloc(c.VkQueueFamilyProperties, queue_count);
    defer allocator.*.free(properties);
    _ = c.vkGetPhysicalDeviceQueueFamilyProperties(instance.*.physical_device, &queue_count, properties.ptr);

    var first_compatible: u32 = 0;
    // Top 10 moments where I love zig
    for (properties, 0..queue_count) |property, i| {
        if ((property.queueFlags & flags) == flags and first_compatible == 0) {
            first_compatible = @intCast(i);
        }
    }

    std.debug.print("[Info] First compatible: {}\n", .{first_compatible});

    const queue_create_info = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = first_compatible,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    };

    // TODO add a way to specify device features
    const device_features: c.VkPhysicalDeviceFeatures = undefined;

    const create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_info,
        .queueCreateInfoCount = 1,
        .pEnabledFeatures = &device_features,
        .enabledExtensionCount = device_extensions.len,
        .ppEnabledExtensionNames = &device_extensions,
        .enabledLayerCount = validation_layers.len,
        .ppEnabledLayerNames = &validation_layers,
    };

    const device_creation_success = c.vkCreateDevice(instance.physical_device, &create_info, null, &instance.device);
    if (device_creation_success != c.VK_SUCCESS) {
        return VkAbstractionError.DeviceCreationFailure;
    }

    // This returns void?
    c.vkGetDeviceQueue(instance.device, first_compatible, 0, &instance.graphics_queue);
}

/// The formats returned in swapchain_support must be freed later
fn query_swapchain_candidate(instance: *Instance, allocator: *const std.mem.Allocator) VkAbstractionError!swapchain_support {
    var result = swapchain_support{};

    const surface_capabilities_success = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(instance.physical_device, &instance.surface, &result.capabilities);
    if (surface_capabilities_success != c.VK_SUCCESS) {
        return VkAbstractionError.unabletoretrievephysicaldevicesurfacecapabilities;
    }

    var format_count = 0;
    c.vkGetPhysicalDeviceSurfaceFormatsKHR(instance.physical_device, instance.surface, &format_count, null);
    std.debug.print("Surface format count: {}", .{format_count});

    if (format_count > 0) {
        result.formats = allocator.*.alloc(format_count, c.VkSurfaceFormatKHR);

        const retrieve_formats_success = c.vkGetPhysicalDeviceSurfaceFormatsKHR(instance.physical_device, instance.surface, &format_count, result.formats);
        if (retrieve_formats_success != c.VK_SUCCESS) {
            return VkAbstractionError.UnableToRetrieveSurfaceFormat;
        }
        result.formats_size = format_count;
    }

    return result;
}

fn create_swapchain(instance : *Instance) VkAbstractionError!void {
    
}

fn instance_clean_up(instance: *Instance) void {
    c.glfwDestroyWindow(instance.window);
    c.glfwTerminate();
}
