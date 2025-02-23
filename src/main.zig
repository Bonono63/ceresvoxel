//Proceeds to zig all over the place...
const std = @import("std");

const c = @import("clibs.zig");

const ENGINE_NAME = "CeresVoxel";

const simple_vert = @embedFile("shaders/simple.vert.spv");
const simple_frag = @embedFile("shaders/simple.frag.spv");

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
    UnableToGetPhysicalDevicePresentModes,
    UnableToRetrieveSurfaceFormat,
    PhysicalDeviceDoesntHaveAppropriateSwapchainSupport,
    UnableToCreateSwapchain,
    UnableToGetSwapchainImages,
    UnableToCreateSwapchainImageViews,
    InappropriateGLFWFrameBufferSizeReturn,
    UnableToCreateShaderModule,
    ShaderFileInvalidFileSize,
    UnableToReadShaderFile,
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
    swapchain_image_count: u32 = undefined,
    swapchain_images: []c.VkImage = undefined,
    swapchain_image_views: []c.VkImageView = undefined,
    swapchain_extent: c.VkExtent2D = undefined,
    REQUIRE_FAMILIES: u32 = c.VK_QUEUE_GRAPHICS_BIT,
};

const swapchain_support = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR = undefined,
    formats: []c.VkSurfaceFormatKHR = undefined,
    formats_size: u32 = 0,
    present_modes: []c.VkPresentModeKHR = undefined,
    present_size: u32 = 0,
};

pub fn main() !void {
    var instance: Instance = .{};

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    const allocator = arena.allocator();

    // TODO add some error handling where possible, although for most of this initialization stuff chances are we won't
    // be able to load into any kind of application if this all doesn't work out...
    try glfw_initialization();

    try window_setup("Engine Test", &instance, &allocator);

    try create_surface(&instance);

    try pick_physical_device(&instance, &allocator);

    try create_graphics_queue(&instance, &allocator);

    try create_swapchain(&instance, &allocator);

    try create_swapchain_image_views(&instance, &allocator);

    try create_graphics_pipeline(&instance, &allocator);

    instance_clean_up(&instance, &allocator);
}

fn glfw_initialization() VkAbstractionError!void {
    if (c.glfwInit() != c.GLFW_TRUE) {
        return VkAbstractionError.GLFWInitialization;
    }

    const vulkan_supported = c.glfwVulkanSupported();
    if (vulkan_supported == c.GLFW_TRUE) {
        std.debug.print("[Info] Vulkan support is enabled\n", .{});
    } else {
        std.debug.print("[Error] Vulkan is not supported\n", .{});
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

    std.debug.print("[Info] Vulkan Application Info:\n", .{});
    std.debug.print("\tApplication name: {s}\n", .{application_info.pApplicationName});
    std.debug.print("\tEngine name: {s}\n", .{application_info.pEngineName});

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

    std.debug.print("[Info] Vulkan Instance Extensions:\n", .{});
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
    const success = c.glfwCreateWindowSurface(instance.vk_instance, instance.window, null, &instance.surface);

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

    std.debug.print("[Info] API version: {any}\n[Info] Driver version: {any}\n[Info] Device name: {s}\n", .{ device_properties.apiVersion, device_properties.driverVersion, device_properties.deviceName });

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
fn query_swapchain_support(instance: *Instance, allocator: *const std.mem.Allocator) VkAbstractionError!swapchain_support {
    var result = swapchain_support{};

    const surface_capabilities_success = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(instance.physical_device, instance.surface, &result.capabilities);
    if (surface_capabilities_success != c.VK_SUCCESS) {
        return VkAbstractionError.UnableToRetrievePhysicalDeviceSurfaceCapabilities;
    }

    var format_count: u32 = 0;
    const get_physical_device_surface_formats = c.vkGetPhysicalDeviceSurfaceFormatsKHR(instance.physical_device, instance.surface, &format_count, null);
    std.debug.print("[Info] Surface format count: {}\n", .{format_count});

    if (get_physical_device_surface_formats != c.VK_SUCCESS) {
        return VkAbstractionError.UnableToRetrieveSurfaceFormat;
    }

    if (format_count > 0) {
        result.formats = try allocator.*.alloc(c.VkSurfaceFormatKHR, format_count);

        const retrieve_formats_success = c.vkGetPhysicalDeviceSurfaceFormatsKHR(instance.physical_device, instance.surface, &format_count, result.formats.ptr);
        if (retrieve_formats_success != c.VK_SUCCESS) {
            return VkAbstractionError.UnableToRetrieveSurfaceFormat;
        }
        result.formats_size = format_count;
    }

    var present_modes: u32 = 0;
    var get_physical_device_present_modes = c.vkGetPhysicalDeviceSurfacePresentModesKHR(instance.physical_device, instance.surface, &present_modes, null);
    if (get_physical_device_present_modes != c.VK_SUCCESS) {
        return VkAbstractionError.UnableToGetPhysicalDevicePresentModes;
    }

    std.debug.print("[Info] Presentation Count: {}\n", .{present_modes});

    if (present_modes != 0) {
        result.present_modes = try allocator.*.alloc(c.VkPresentModeKHR, present_modes);

        get_physical_device_present_modes = c.vkGetPhysicalDeviceSurfacePresentModesKHR(instance.physical_device, instance.surface, &present_modes, result.present_modes.ptr);
        if (get_physical_device_present_modes != c.VK_SUCCESS) {
            return VkAbstractionError.UnableToGetPhysicalDevicePresentModes;
        }

        result.present_size = present_modes;
    }

    return result;
}

fn create_swapchain(instance: *Instance, allocator: *const std.mem.Allocator) VkAbstractionError!void {
    const support = try query_swapchain_support(instance, allocator);

    if (support.present_size > 0 and support.formats_size > 0) {
        var surface_format: c.VkSurfaceFormatKHR = undefined;
        const image_count: u32 = support.capabilities.minImageCount + 1;
        var format_index: u32 = 0;

        for (0..support.formats_size) |i| {
            if (support.formats[i].format == c.VK_FORMAT_B8G8R8A8_SRGB and support.formats[i].colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                format_index = @intCast(i);
                surface_format = support.formats[i];
                break;
            }
        }

        var present_mode: u32 = c.VK_PRESENT_MODE_FIFO_KHR;
        for (0..support.present_size) |i| {
            if (support.present_modes[i] == c.VK_PRESENT_MODE_MAILBOX_KHR) {
                present_mode = c.VK_PRESENT_MODE_MAILBOX_KHR;
            }
        }

        var extent: c.VkExtent2D = undefined;
        var width: i32 = 0;
        var height: i32 = 0;
        _ = &width;
        std.debug.print("[Info] current extent: {} {}\n", .{ support.capabilities.currentExtent.width, support.capabilities.currentExtent.height });
        if (support.capabilities.currentExtent.width != std.math.maxInt(u32)) {
            extent = support.capabilities.currentExtent;
        } else {
            // This returns a signed integer
            c.glfwGetFramebufferSize(instance.window, &width, &height);

            if (width < 0 or height < 0) {
                return VkAbstractionError.InappropriateGLFWFrameBufferSizeReturn;
            }

            // This required unsigned integers...
            extent.width = @intCast(width);
            extent.height = @intCast(height);

            extent.width = std.math.clamp(extent.width, support.capabilities.minImageExtent.width, support.capabilities.maxImageExtent.width);
            extent.height = std.math.clamp(extent.height, support.capabilities.minImageExtent.height, support.capabilities.maxImageExtent.height);
            std.debug.print("[Info] Final extent: {} {}\n", .{ extent.width, extent.height });

            const swapchain_create_info = c.VkSwapchainCreateInfoKHR{
                .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
                .surface = instance.surface,
                .minImageCount = image_count,
                .imageFormat = surface_format.format,
                .imageColorSpace = surface_format.colorSpace,
                .imageExtent = extent,
                .imageArrayLayers = 1,
                .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
                .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
                .queueFamilyIndexCount = 0,
                .pQueueFamilyIndices = null,
                .preTransform = support.capabilities.currentTransform,
                .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
                .presentMode = present_mode,
                .clipped = c.VK_TRUE,
                // This should be VK_NULL_HANDLE, but that is a opaque type and can't be casted properly,
                // After a quick look at the vulkan docs it appears to have cpp and msvc specific exceptions
                // however, our zig build should be compiling it in c and zig shouldn't be relying on
                // msvc either so replacing it with null outright should be ok...
                .oldSwapchain = null,
            };

            const swapchain_creation_success = c.vkCreateSwapchainKHR(instance.device, &swapchain_create_info, null, &instance.swapchain);
            if (swapchain_creation_success != c.VK_SUCCESS) {
                return VkAbstractionError.UnableToCreateSwapchain;
            }

            const get_swapchain_images_success = c.vkGetSwapchainImagesKHR(instance.device, instance.swapchain, &instance.swapchain_image_count, null);

            if (get_swapchain_images_success != c.VK_SUCCESS) {
                return VkAbstractionError.UnableToGetSwapchainImages;
            }

            std.debug.print("[Info] Swapchain final image count: {}\n", .{instance.swapchain_image_count});

            instance.swapchain_images = try allocator.*.alloc(c.VkImage, instance.swapchain_image_count);
            const get_swapchain_images_KHR = c.vkGetSwapchainImagesKHR(instance.device, instance.swapchain, &instance.swapchain_image_count, instance.swapchain_images.ptr);

            if (get_swapchain_images_KHR != c.VK_SUCCESS) {
                return VkAbstractionError.UnableToGetSwapchainImages;
            }

            instance.swapchain_format = surface_format;
            instance.swapchain_extent = extent;

            allocator.*.free(support.formats);
            allocator.*.free(support.present_modes);
        }
    } else {
        return VkAbstractionError.PhysicalDeviceDoesntHaveAppropriateSwapchainSupport;
    }
}

fn create_swapchain_image_views(instance: *Instance, allocator: *const std.mem.Allocator) VkAbstractionError!void {
    instance.swapchain_image_views = try allocator.*.alloc(c.VkImageView, instance.swapchain_image_count);
    for (0..instance.swapchain_image_count) |i| {
        var create_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = instance.swapchain_images[i],
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = instance.swapchain_format.format,
        };

        create_info.components.r = c.VK_COMPONENT_SWIZZLE_IDENTITY;
        create_info.components.g = c.VK_COMPONENT_SWIZZLE_IDENTITY;
        create_info.components.b = c.VK_COMPONENT_SWIZZLE_IDENTITY;
        create_info.components.a = c.VK_COMPONENT_SWIZZLE_IDENTITY;

        create_info.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        create_info.subresourceRange.baseMipLevel = 0;
        create_info.subresourceRange.levelCount = 1;
        create_info.subresourceRange.baseArrayLayer = 0;
        create_info.subresourceRange.layerCount = 1;

        const imageview_success = c.vkCreateImageView(instance.device, &create_info, null, instance.swapchain_image_views.ptr + i);
        if (imageview_success != c.VK_SUCCESS) {
            return VkAbstractionError.UnableToCreateSwapchainImageViews;
        }
    }
}

fn create_graphics_pipeline(instance: *Instance, allocator: *const std.mem.Allocator) VkAbstractionError!void {
    _ = &instance;

    const vertex_source = try create_shader_module(instance, allocator, "shaders/simple.vert.spv");
    const fragment_source = try create_shader_module(instance, allocator, "shaders/simple.frag.spv");

    const vertex_shader_stage = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertex_source,
        .pName = "main",
    };

    const fragment_shader_stage = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragment_source,
        .pName = "main",
    };

    var shader_stages = std.ArrayList(c.VkPipelineShaderStageCreateInfo).init(allocator.*);
    defer shader_stages.deinit();

    try shader_stages.append(vertex_shader_stage);
    try shader_stages.append(fragment_shader_stage);


    const dynamic_state = [_]c.VkDynamicState{ 
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };

    const dynamic_state_create_info = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamic_state.len,
        .pDynamicStates = dynamic_state.ptr,
    };

    const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INF0,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
    };

    const assembly_create_info = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INF0,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    const viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = instance.swapchain_extent.width,
        .height = instance.swapchain_extent.height,
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor = c.VkRect2D{
        .offset = .{0, 0},
        .extent = instance.swapchain_extent,
    };

    const viewport_create_info = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };

    const rasterization_create_info = c.VkPipelineRasterizationStateCreateInfo{
            
    };
}

fn create_shader_module(instance: *Instance, allocator: *const std.mem.Allocator, file_name: []const u8) VkAbstractionError!c.VkShaderModule {
    var shader_module: c.VkShaderModule = undefined;

    const source = try read_sprv_file_aligned(allocator, file_name);
    defer allocator.*.free(source);

    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        // Size of the source in bytes not u32
        .codeSize = source.len * 4,
        // This must be aligned to 4 bytes
        .pCode = source.ptr,
    };

    const create_shader_module_success = c.vkCreateShaderModule(instance.device, &create_info, null, &shader_module);
    if (create_shader_module_success != c.VK_SUCCESS) {
        return VkAbstractionError.UnableToCreateShaderModule;
    }

    return shader_module;
}

/// Creates a 4 byte aligned buffer of any given file, intended for reading SPIR-V binary files
fn read_sprv_file_aligned(allocator: *const std.mem.Allocator, file_name: []const u8) VkAbstractionError![]u32 {
    const file_array = std.fs.cwd().readFileAlloc(allocator.*, file_name, 3000) catch |err| {
        std.debug.print("[Error] [IO] {}", .{err});
        return VkAbstractionError.UnableToReadShaderFile;
    };

    var array = std.ArrayListAligned(u32, @sizeOf(u32)).init(allocator.*);

    std.debug.print("[Info] {s} length: {} divided by 4: {}\n", .{ file_name, file_array.len, file_array.len / 4 });

    if (file_array.len % 4 != 0) {
        return VkAbstractionError.ShaderFileInvalidFileSize;
    }

    for (0..file_array.len / 4) |i| {
        const item: u32 = @as(u32, file_array[i * 4 + 3]) << 24 | @as(u32, file_array[i * 4 + 2]) << 16 | @as(u32, file_array[i * 4 + 1]) << 8 | @as(u32, file_array[i * 4]);
        try array.append(item);
    }

    return array.items;
}

// TODO make sure to free like 70% of the objects I haven't bothered to, likely memoryy leaks in the swapchain code
fn instance_clean_up(instance: *Instance, allocator: *const std.mem.Allocator) void {
    _ = allocator;
    //allocator.*.free(instance.swapchain_image_views);
    c.glfwDestroyWindow(instance.window);
    c.glfwTerminate();
}
