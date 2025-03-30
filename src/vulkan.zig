const std = @import("std");
const c = @import("clibs.zig");

// Attempt at descriptive Errors
pub const VkAbstractionError = error{
    Success,
    OutOfMemory,
    GLFWInitializationFailed,
    GLFWErrorCallbackFailure,
    NullWindow,
    NullRequiredInstances,
    VkInstanceCreationFailure,
    SurfaceCreationFailed,
    VulkanUnavailable,
    PhysicalDevicesCountFailure,
    EnumeratePhysicalDevicesFailure,
    InvalidDeviceCount,
    EnumeratePhysicalDevicesFailed,
    DeviceCreationFailure,
    RetrievePhysicalDeviceSurfaceCapabilitiesFailed,
    GetPhysicalDevicePresentModesFailure,
    RetrieveSurfaceFormatFailure,
    PhysicalDeviceInappropriateSwapchainSupport,
    CreateSwapchainFailed,
    GetSwapchainImagesFailed,
    CreateSwapchainImageViewsFailed,
    InappropriateGLFWFrameBufferSizeReturn,
    CreateShaderModuleFailed,
    ShaderFileInvalidFileSize,
    ReadShaderFileFailed,
    CreatePipelineLayoutFailed,
    FailedCreatingRenderPass,
    FailedCreatingGraphicsPipeline,
    FramebufferCreationFailed,
    FailedCommandPoolCreation,
    CommandBufferAllocationFailed,
    BeginRenderPassFailed,
    CompleteRenderPassFailed,
    InstanceLayerEnumerationFailed,
    CreateSyncObjectsFailed,
    EndRecordingFailure,
    AcquireNextSwapchainImageFailed,
    PresentationFailure,
};

// These parameters are the minimum required for what we want to do
const instance_extensions = [_][*:0]const u8{
    "VK_KHR_display",
};

const validation_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
    //"VK_LAYER_RENDERDOC_Capture",
};

const device_extensions = [_][*:0]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const swapchain_support = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR = undefined,
    formats: []c.VkSurfaceFormatKHR = undefined,
    present_modes: []c.VkPresentModeKHR = undefined,
};

pub const Vertex = struct {
    pos: c.vec2,
    color: c.vec3,
};

pub const Mesh = struct {
    vertices: []Vertex = undefined,
    binding_description: []c.VkVertexInputBindingDescription = undefined,
    attribute_description: []c.VkVertexInputAttributeDescription = undefined,
};

// The vulkan/render state
pub const Instance = struct {
    REQUIRE_FAMILIES: u32 = c.VK_QUEUE_GRAPHICS_BIT,
    MAX_CONCURRENT_FRAMES: u32 = 2,

    allocator: *const std.mem.Allocator = undefined,

    vk_instance: c.VkInstance = undefined,
    window: *c.GLFWwindow = undefined,
    surface: c.VkSurfaceKHR = undefined,

    physical_device: c.VkPhysicalDevice = undefined,
    device: c.VkDevice = undefined,
    queue_family_index: u32 = 0,
    present_queue: c.VkQueue = undefined,

    swapchain: c.VkSwapchainKHR = undefined,
    swapchain_format: c.VkSurfaceFormatKHR = undefined,
    swapchain_images: []c.VkImage = undefined,
    swapchain_image_views: []c.VkImageView = undefined,
    swapchain_extent: c.VkExtent2D = undefined,

    framebuffer_resized: bool = false,

    shader_modules: std.ArrayList(c.VkShaderModule) = undefined,

    pipeline_layout: c.VkPipelineLayout = undefined,
    renderpass: c.VkRenderPass = undefined,
    graphics_pipeline: c.VkPipeline = undefined,
    frame_buffers: []c.VkFramebuffer = undefined,

    command_pool: c.VkCommandPool = undefined,
    command_buffers: []c.VkCommandBuffer = undefined,

    image_available_semaphore: []c.VkSemaphore = undefined,
    image_completion_semaphore: []c.VkSemaphore = undefined,
    in_flight_fence: []c.VkFence = undefined,

    /// Initializes the general state of Vulkan and GLFW for our rendering
    pub fn initialize_state(self: *Instance, application_name: []const u8, engine_name: []const u8, allocator: *const std.mem.Allocator) VkAbstractionError!void {
        self.allocator = allocator;

        try glfw_initialization();
        try window_setup(self, application_name, engine_name);
        try create_surface(self);
        try pick_physical_device(self);
        try create_present_queue(self, self.REQUIRE_FAMILIES);
        try create_swapchain(self);
        try create_swapchain_image_views(self);

        // TODO this can be done prior to this function and we can defer its deinitialization
        self.shader_modules = std.ArrayList(c.VkShaderModule).init(self.allocator.*);

        try create_graphics_pipeline(self);
        try create_framebuffers(self);
        try create_command_pool(self);

        //TODO move these concurrent frame based allocations to before this function in the main loop (we can use defer :D)
        self.command_buffers = try allocator.alloc(c.VkCommandBuffer, self.MAX_CONCURRENT_FRAMES);
        try create_command_buffers(self);

        self.image_available_semaphore = try self.allocator.alloc(c.VkSemaphore, self.MAX_CONCURRENT_FRAMES);
        self.image_completion_semaphore = try self.allocator.alloc(c.VkSemaphore, self.MAX_CONCURRENT_FRAMES);
        self.in_flight_fence = try self.allocator.alloc(c.VkFence, self.MAX_CONCURRENT_FRAMES);
        try create_sync_objects(self);
    }

    /// Initializes GLFW and checks for Vulkan support
    fn glfw_initialization() VkAbstractionError!void {
        if (c.glfwInit() != c.GLFW_TRUE) {
            return VkAbstractionError.GLFWInitializationFailed;
        }

        const vulkan_support = c.glfwVulkanSupported();
        if (vulkan_support != c.GLFW_TRUE) {
            std.debug.print("[Error] GLFW could not find Vulkan support.\n", .{});
            return VkAbstractionError.VulkanUnavailable;
        }

        _ = c.glfwSetErrorCallback(glfw_error_callback);
    }

    /// Creates our Vulkan instance and GLFW window
    fn window_setup(self: *Instance, application_name: []const u8, engine_name: []const u8) VkAbstractionError!void {
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        // c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

        self.window = c.glfwCreateWindow(800, 600, application_name.ptr, null, null) orelse return VkAbstractionError.NullWindow;

        const application_info = c.VkApplicationInfo{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = application_name.ptr,
            .pEngineName = engine_name.ptr,
            .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = c.VK_API_VERSION_1_3,
        };

        std.debug.print("[Info] Vulkan Application Info:\n", .{});
        std.debug.print("\tApplication name: {s}\n", .{application_info.pApplicationName});
        std.debug.print("\tEngine name: {s}\n", .{application_info.pEngineName});

        var required_extension_count: u32 = 0;
        const required_extensions = c.glfwGetRequiredInstanceExtensions(&required_extension_count) orelse return VkAbstractionError.NullRequiredInstances;

        var extensions_arraylist = std.ArrayList([*:0]const u8).init(self.allocator.*);
        defer extensions_arraylist.deinit();

        for (0..required_extension_count) |i| {
            try extensions_arraylist.append(required_extensions[i]);
        }

        for (instance_extensions) |extension| {
            try extensions_arraylist.append(extension);
        }

        std.debug.print("[Info] Vulkan Instance Extensions ({}):\n", .{extensions_arraylist.items.len});
        for (extensions_arraylist.items) |item| {
            std.debug.print("\t{s}\n", .{item});
        }

        var available_layers_count: u32 = 0;
        if (c.vkEnumerateInstanceLayerProperties(&available_layers_count, null) != c.VK_SUCCESS) {
            return VkAbstractionError.InstanceLayerEnumerationFailed;
        }

        const available_layers = try self.allocator.*.alloc(c.VkLayerProperties, available_layers_count);
        defer self.allocator.*.free(available_layers);

        const enumeration_success = c.vkEnumerateInstanceLayerProperties(&available_layers_count, available_layers.ptr);
        if (enumeration_success != c.VK_SUCCESS) {
            std.debug.print("[Error] Enumeration failure: {}\n", .{enumeration_success});
            return VkAbstractionError.InstanceLayerEnumerationFailed;
        }

        std.debug.print("[Info] Available validation layers ({}):\n", .{available_layers.len});
        for (available_layers) |validation_layer| {
            std.debug.print("\t{s}\n", .{validation_layer.layerName});
        }

        std.debug.print("[Info] Vulkan Instance Validation layers ({}):\n", .{validation_layers.len});
        for (validation_layers) |validation_layer| {
            std.debug.print("\t{s}\n", .{validation_layer});
        }

        const create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &application_info,
            .enabledLayerCount = @intCast(validation_layers.len),
            .ppEnabledLayerNames = &validation_layers,
            .enabledExtensionCount = @intCast(extensions_arraylist.items.len),
            .ppEnabledExtensionNames = extensions_arraylist.items.ptr,
        };

        const instance_result = c.vkCreateInstance(&create_info, null, &self.vk_instance);

        if (instance_result != c.VK_SUCCESS) {
            std.debug.print("[Error] Vk Instance Creation Failed: {}\n", .{instance_result});
            return VkAbstractionError.VkInstanceCreationFailure;
        }
    }

    fn create_surface(self: *Instance) VkAbstractionError!void {
        const success = c.glfwCreateWindowSurface(self.vk_instance, self.window, null, &self.surface);

        if (success != c.VK_SUCCESS) {
            std.debug.print("[Error] Surface Creation Failed: {}\n", .{success});
            return VkAbstractionError.SurfaceCreationFailed;
        }
    }

    fn pick_physical_device(self: *Instance) VkAbstractionError!void {
        var device_count: u32 = 0;
        const physical_device_count_success = c.vkEnumeratePhysicalDevices(self.vk_instance, &device_count, null);

        if (physical_device_count_success != c.VK_SUCCESS) {
            std.debug.print("[Error] Unable to enumerate physical devices device_count: {} vk error code: {}\n", .{ device_count, physical_device_count_success });
            return VkAbstractionError.PhysicalDevicesCountFailure;
        }

        if (device_count <= 0) {
            return VkAbstractionError.InvalidDeviceCount;
        }

        const devices = try self.allocator.*.alloc(c.VkPhysicalDevice, device_count);
        defer self.allocator.*.free(devices);
        const enumerate_physical_devices_success = c.vkEnumeratePhysicalDevices(self.vk_instance, &device_count, devices.ptr);

        if (enumerate_physical_devices_success != c.VK_SUCCESS) {
            std.debug.print("[Error] Unable to enumerate physical devices device_count: {} vk error code: {}\n", .{ device_count, enumerate_physical_devices_success });
            return VkAbstractionError.EnumeratePhysicalDevicesFailure;
        }

        self.physical_device = devices[0];

        var device_properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(self.physical_device, &device_properties);

        std.debug.print("[Info] API version: {any}\n[Info] Driver version: {any}\n[Info] Device name: {s}\n", .{ device_properties.apiVersion, device_properties.driverVersion, device_properties.deviceName });

        // TODO Check for device extension compatibility
    }

    fn create_present_queue(self: *Instance, flags: u32) VkAbstractionError!void {
        const priority: f32 = 1.0;

        var queue_count: u32 = 0;
        _ = c.vkGetPhysicalDeviceQueueFamilyProperties(self.*.physical_device, &queue_count, null);
        std.debug.print("[Info] Queue count: {}\n", .{queue_count});

        const properties = try self.allocator.*.alloc(c.VkQueueFamilyProperties, queue_count);
        defer self.allocator.*.free(properties);
        _ = c.vkGetPhysicalDeviceQueueFamilyProperties(self.*.physical_device, &queue_count, properties.ptr);

        var first_compatible: u32 = 0;
        // Top 10 moments where I love zig
        for (properties, 0..queue_count) |property, i| {
            if ((property.queueFlags & flags) == flags and first_compatible == 0) {
                first_compatible = @intCast(i);
            }
        }

        std.debug.print("[Info] First compatible: {}\n", .{first_compatible});

        self.queue_family_index = first_compatible;

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

        const device_creation_success = c.vkCreateDevice(self.physical_device, &create_info, null, &self.device);
        if (device_creation_success != c.VK_SUCCESS) {
            return VkAbstractionError.DeviceCreationFailure;
        }

        c.vkGetDeviceQueue(self.device, first_compatible, 0, &self.present_queue);
    }

    /// The formats returned in swapchain_support must be freed later
    fn query_swapchain_support(self: *Instance) VkAbstractionError!swapchain_support {
        var result = swapchain_support{};

        const surface_capabilities_success = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(self.physical_device, self.surface, &result.capabilities);
        if (surface_capabilities_success != c.VK_SUCCESS) {
            return VkAbstractionError.RetrievePhysicalDeviceSurfaceCapabilitiesFailed;
        }

        var format_count: u32 = 0;
        const get_physical_device_surface_formats = c.vkGetPhysicalDeviceSurfaceFormatsKHR(self.physical_device, self.surface, &format_count, null);
        std.debug.print("[Info] Surface format count: {}\n", .{format_count});

        if (get_physical_device_surface_formats != c.VK_SUCCESS or format_count < 0) {
            return VkAbstractionError.RetrieveSurfaceFormatFailure;
        }

        result.formats = try self.allocator.*.alloc(c.VkSurfaceFormatKHR, format_count);

        const retrieve_formats_success = c.vkGetPhysicalDeviceSurfaceFormatsKHR(self.physical_device, self.surface, &format_count, result.formats.ptr);
        if (retrieve_formats_success != c.VK_SUCCESS) {
            return VkAbstractionError.RetrieveSurfaceFormatFailure;
        }
        //result.formats_size = format_count;

        var present_modes: u32 = 0;
        var get_physical_device_present_modes = c.vkGetPhysicalDeviceSurfacePresentModesKHR(self.physical_device, self.surface, &present_modes, null);
        if (get_physical_device_present_modes != c.VK_SUCCESS or present_modes < 0) {
            return VkAbstractionError.GetPhysicalDevicePresentModesFailure;
        }

        std.debug.print("[Info] Presentation Count: {}\n", .{present_modes});

        result.present_modes = try self.allocator.*.alloc(c.VkPresentModeKHR, present_modes);

        get_physical_device_present_modes = c.vkGetPhysicalDeviceSurfacePresentModesKHR(self.physical_device, self.surface, &present_modes, result.present_modes.ptr);
        if (get_physical_device_present_modes != c.VK_SUCCESS) {
            return VkAbstractionError.GetPhysicalDevicePresentModesFailure;
        }

        //result.present_size = present_modes;

        return result;
    }

    fn create_swapchain(self: *Instance) VkAbstractionError!void {
        const support = try query_swapchain_support(self);
        defer self.allocator.*.free(support.formats);
        defer self.allocator.*.free(support.present_modes);

        //if (support.present_size > 0 and support.formats_size > 0) {
        var surface_format: c.VkSurfaceFormatKHR = support.formats[0];
        var image_count: u32 = support.capabilities.minImageCount + 1;
        var format_index: u32 = 0;

        for (support.formats, 0..support.formats.len) |format, i| {
            if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                format_index = @intCast(i);
                surface_format = format;
                break;
            }
        }

        var present_mode: u32 = c.VK_PRESENT_MODE_FIFO_KHR;
        for (support.present_modes) |mode| {
            if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
                present_mode = c.VK_PRESENT_MODE_MAILBOX_KHR;
            }
        }

        var extent: c.VkExtent2D = undefined;
        var width: i32 = 0;
        var height: i32 = 0;
        std.debug.print("[Info] current extent: {} {}\n", .{ support.capabilities.currentExtent.width, support.capabilities.currentExtent.height });
        if (support.capabilities.currentExtent.width != std.math.maxInt(u32)) {
            extent = support.capabilities.currentExtent;
        } else {
            // This returns a signed integer
            c.glfwGetFramebufferSize(self.window, &width, &height);

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
                .surface = self.surface,
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

            const swapchain_creation_success = c.vkCreateSwapchainKHR(self.device, &swapchain_create_info, null, &self.swapchain);
            if (swapchain_creation_success != c.VK_SUCCESS) {
                return VkAbstractionError.CreateSwapchainFailed;
            }

            const get_swapchain_images_success = c.vkGetSwapchainImagesKHR(self.device, self.swapchain, &image_count, null);

            if (get_swapchain_images_success != c.VK_SUCCESS) {
                return VkAbstractionError.GetSwapchainImagesFailed;
            }

            self.swapchain_images = try self.allocator.*.alloc(c.VkImage, image_count);
            const get_swapchain_images_KHR = c.vkGetSwapchainImagesKHR(self.device, self.swapchain, &image_count, self.swapchain_images.ptr);

            if (get_swapchain_images_KHR != c.VK_SUCCESS) {
                return VkAbstractionError.GetSwapchainImagesFailed;
            }

            self.swapchain_format = surface_format;
            self.swapchain_extent = extent;

            std.debug.print("[Info] Swapchain final image count: {}\n", .{self.swapchain_images.len});
        }
    }

    fn create_swapchain_image_views(self: *Instance) VkAbstractionError!void {
        self.swapchain_image_views = try self.allocator.*.alloc(c.VkImageView, self.swapchain_images.len);
        for (0..self.swapchain_images.len) |i| {
            var create_info = c.VkImageViewCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = self.swapchain_images[i],
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = self.swapchain_format.format,
                .components = .{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            const imageview_success = c.vkCreateImageView(self.device, &create_info, null, self.swapchain_image_views.ptr + i);
            if (imageview_success != c.VK_SUCCESS) {
                return VkAbstractionError.CreateSwapchainImageViewsFailed;
            }
        }
    }

    fn create_graphics_pipeline(self: *Instance) VkAbstractionError!void {
        try create_shader_module(self, self.allocator, "shaders/simple.vert.spv");
        try create_shader_module(self, self.allocator, "shaders/simple.frag.spv");

        const vertex_shader_stage = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = self.shader_modules.items[0],
            .pName = "main",
        };

        const fragment_shader_stage = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = self.shader_modules.items[1],
            .pName = "main",
        };

        var shader_stages = std.ArrayList(c.VkPipelineShaderStageCreateInfo).init(self.allocator.*);
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
            .pDynamicStates = &dynamic_state,
        };

        var binding_description: []c.VkVertexInputBindingDescription = undefined;
        binding_description = try self.allocator.*.alloc(c.VkVertexInputBindingDescription, 1);
        binding_description[0] = .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        var attribute_description: []c.VkVertexInputAttributeDescription = undefined;
        attribute_description = try self.allocator.*.alloc(c.VkVertexInputAttributeDescription, 2);
        attribute_description[0] = .{ .binding = 0, .location = 0, .format = c.VK_FORMAT_R32G32_SFLOAT, .offset = 0 };
        attribute_description[1] = .{ .binding = 0, .location = 1, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = 8 };

        const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = @intCast(binding_description.len),
            .pVertexBindingDescriptions = binding_description.ptr,
            .vertexAttributeDescriptionCount = @intCast(attribute_description.len),
            .pVertexAttributeDescriptions = attribute_description.ptr,
        };

        const assembly_create_info = c.VkPipelineInputAssemblyStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        };

        const viewport = c.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(self.swapchain_extent.width),
            .height = @floatFromInt(self.swapchain_extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };

        const scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain_extent,
        };

        const viewport_create_info = c.VkPipelineViewportStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .pViewports = &viewport,
            .scissorCount = 1,
            .pScissors = &scissor,
        };

        const rasterization_create_info = c.VkPipelineRasterizationStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable = c.VK_FALSE,
            .rasterizerDiscardEnable = c.VK_FALSE,
            .polygonMode = c.VK_POLYGON_MODE_FILL,
            .lineWidth = 1.0,
            .cullMode = c.VK_CULL_MODE_BACK_BIT,
            .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
            .depthBiasEnable = c.VK_FALSE,
            .depthBiasConstantFactor = 0.0,
            .depthBiasClamp = 0.0,
            .depthBiasSlopeFactor = 0.0,
        };

        const multisampling_create_info = c.VkPipelineMultisampleStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .sampleShadingEnable = c.VK_FALSE,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
            .minSampleShading = 1.0,
            .pSampleMask = null,
            .alphaToCoverageEnable = c.VK_FALSE,
            .alphaToOneEnable = c.VK_FALSE,
        };

        const color_blending_attachment_create_info = c.VkPipelineColorBlendAttachmentState{
            .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
            .blendEnable = c.VK_FALSE,
        };

        const color_blending_create_info = c.VkPipelineColorBlendStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = c.VK_FALSE,
            .logicOp = c.VK_LOGIC_OP_COPY,
            .attachmentCount = 1,
            .pAttachments = &color_blending_attachment_create_info,
        };

        // This is for shader uniforms
        const pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 0,
            .pSetLayouts = null,
            .pushConstantRangeCount = 0,
            .pPushConstantRanges = null,
        };

        const pipeline_layout_success = c.vkCreatePipelineLayout(self.device, &pipeline_layout_create_info, null, &self.pipeline_layout);

        if (pipeline_layout_success != c.VK_SUCCESS) {
            return VkAbstractionError.CreatePipelineLayoutFailed;
        }

        const color_attachment = c.VkAttachmentDescription{
            .format = self.swapchain_format.format,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        const color_attachment_ref = c.VkAttachmentReference{
            .attachment = 0,
            .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const subpass = c.VkSubpassDescription{
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = 1,
            .pColorAttachments = &color_attachment_ref,
        };

        // Ensure the renderpass is waiting for our frames to complete
        const subpass_dependency = c.VkSubpassDependency{
            .srcSubpass = c.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = 0,
            .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        };

        const renderpass_create_info = c.VkRenderPassCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = 1,
            .pAttachments = &color_attachment,
            .subpassCount = 1,
            .pSubpasses = &subpass,
            .dependencyCount = 1,
            .pDependencies = &subpass_dependency,
        };

        const render_pass_creation = c.vkCreateRenderPass(self.device, &renderpass_create_info, null, &self.renderpass);
        if (render_pass_creation != c.VK_SUCCESS) {
            return VkAbstractionError.FailedCreatingRenderPass;
        }

        const pipeline_create_info = c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount = @intCast(shader_stages.items.len),
            .pStages = shader_stages.items.ptr,
            .pVertexInputState = &vertex_input_info,
            .pInputAssemblyState = &assembly_create_info,
            .pViewportState = &viewport_create_info,
            .pRasterizationState = &rasterization_create_info,
            .pMultisampleState = &multisampling_create_info,
            .pDepthStencilState = null,
            .pColorBlendState = &color_blending_create_info,
            .pDynamicState = &dynamic_state_create_info,
            .layout = self.pipeline_layout,
            .renderPass = self.renderpass,
            .subpass = 0,
        };

        const pipeline_success = c.vkCreateGraphicsPipelines(self.device, null, 1, &pipeline_create_info, null, &self.graphics_pipeline);
        if (pipeline_success != c.VK_SUCCESS) {
            return VkAbstractionError.FailedCreatingGraphicsPipeline;
        }
    }

    /// Creates a shader module and appends the handler to the state's shader array list
    fn create_shader_module(self: *Instance, allocator: *const std.mem.Allocator, file_name: []const u8) VkAbstractionError!void {
        var shader_module: c.VkShaderModule = undefined;

        const source = try read_sprv_file_aligned(allocator, file_name);
        defer source.deinit();

        const create_info = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            // Size of the source in bytes not u32
            .codeSize = source.items.len * 4,
            // This must be aligned to 4 bytes
            .pCode = source.items.ptr,
        };

        const create_shader_module_success = c.vkCreateShaderModule(self.device, &create_info, null, &shader_module);
        if (create_shader_module_success != c.VK_SUCCESS) {
            return VkAbstractionError.CreateShaderModuleFailed;
        }

        try self.shader_modules.append(shader_module);
    }

    /// Creates a 4 byte aligned buffer of any given file, intended for reading SPIR-V binary files
    fn read_sprv_file_aligned(allocator: *const std.mem.Allocator, file_name: []const u8) VkAbstractionError!std.ArrayListAligned(u32, @sizeOf(u32)) {
        const file_array = std.fs.cwd().readFileAlloc(allocator.*, file_name, 10000) catch |err| {
            std.debug.print("[Error] [IO] {}", .{err});
            return VkAbstractionError.ReadShaderFileFailed;
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

        return array;
    }

    fn create_framebuffers(self: *Instance) VkAbstractionError!void {
        self.frame_buffers = try self.allocator.*.alloc(c.VkFramebuffer, self.swapchain_image_views.len);

        for (self.swapchain_image_views, 0..self.swapchain_image_views.len) |image_view, i| {
            const framebuffer_create_info = c.VkFramebufferCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass = self.renderpass,
                .attachmentCount = 1,
                .pAttachments = &image_view,
                .width = self.swapchain_extent.width,
                .height = self.swapchain_extent.height,
                .layers = 1,
            };

            const framebuffer_success = c.vkCreateFramebuffer(self.device, &framebuffer_create_info, null, &self.frame_buffers[i]);
            if (framebuffer_success != c.VK_SUCCESS) {
                return VkAbstractionError.FramebufferCreationFailed;
            }
        }
    }

    fn create_command_pool(self: *Instance) VkAbstractionError!void {
        const command_pool_info = c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = self.queue_family_index,
        };

        const command_pool_success = c.vkCreateCommandPool(self.device, &command_pool_info, null, &self.command_pool);
        if (command_pool_success != c.VK_SUCCESS) {
            return VkAbstractionError.FailedCommandPoolCreation;
        }
    }

    fn create_command_buffers(self: *Instance) VkAbstractionError!void {
        const allocation_info = c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = self.command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(self.command_buffers.len),
        };

        if (c.vkAllocateCommandBuffers(self.device, &allocation_info, self.command_buffers.ptr) != c.VK_SUCCESS) {
            return VkAbstractionError.CommandBufferAllocationFailed;
        }
    }

    fn record_command_buffer(self: *Instance, command_buffer: c.VkCommandBuffer, image_index: u32, buffers: []c.VkBuffer, vertex_count: u32) VkAbstractionError!void {
        const begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = 0,
            //.pInheretenceInfo = null,
        };

        if (c.vkBeginCommandBuffer(command_buffer, &begin_info) != c.VK_SUCCESS) {
            return VkAbstractionError.BeginRenderPassFailed;
        }

        const clear_color: c.VkClearValue = undefined;
        //std.debug.print("clear color [0]: {}\n", .{clear_color});

        const render_pass_info = c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = self.renderpass,
            .framebuffer = self.frame_buffers[image_index],
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swapchain_extent,
            },
            .clearValueCount = 1,
            .pClearValues = &clear_color,
        };

        c.vkCmdBeginRenderPass(command_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);

        c.vkCmdBindPipeline(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.graphics_pipeline);

        const offsets: [1]c.VkDeviceSize = .{0};
        c.vkCmdBindVertexBuffers(command_buffer, 0, 1, buffers.ptr, &offsets);

        const viewport = c.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(self.swapchain_extent.width),
            .height = @floatFromInt(self.swapchain_extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };

        c.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

        const scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain_extent,
        };

        c.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

        c.vkCmdDraw(command_buffer, vertex_count, 1, 0, 0);

        c.vkCmdEndRenderPass(command_buffer);
    }

    fn create_sync_objects(self: *Instance) VkAbstractionError!void {
        const image_available_semaphore_info = c.VkSemaphoreCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        const image_completion_semaphore_info = c.VkSemaphoreCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        const in_flight_fence_info = c.VkFenceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        for (0..self.MAX_CONCURRENT_FRAMES) |i| {
            const success_a = c.vkCreateSemaphore(self.device, &image_available_semaphore_info, null, &self.image_available_semaphore[i]);
            const success_b = c.vkCreateSemaphore(self.device, &image_completion_semaphore_info, null, &self.image_completion_semaphore[i]);
            const success_c = c.vkCreateFence(self.device, &in_flight_fence_info, null, &self.in_flight_fence[i]);

            if (success_a != c.VK_SUCCESS or success_b != c.VK_SUCCESS or success_c != c.VK_SUCCESS) {
                return VkAbstractionError.CreateSyncObjectsFailed;
            }
        }
    }

    pub fn draw_frame(self: *Instance, frame_index: u32, buffers: []c.VkBuffer, vertex_count: u32) VkAbstractionError!void {
        const fence_wait = c.vkWaitForFences(self.device, 1, &self.in_flight_fence[frame_index], c.VK_TRUE, std.math.maxInt(u64));

        if (fence_wait != c.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }

        var image_index: u32 = 0;

        const acquire_next_image_success = c.vkAcquireNextImageKHR(self.device, self.swapchain, std.math.maxInt(u64), self.image_available_semaphore[frame_index], null, &image_index);

        if (acquire_next_image_success == c.VK_ERROR_OUT_OF_DATE_KHR or acquire_next_image_success == c.VK_SUBOPTIMAL_KHR or self.framebuffer_resized) {
            try recreate_swapchain(self);
            self.framebuffer_resized = false;
            return;
        } else if (acquire_next_image_success != c.VK_SUCCESS) {
            std.debug.print("[Error] Unable to acquire next swapchain image: {} \n", .{acquire_next_image_success});
            return VkAbstractionError.AcquireNextSwapchainImageFailed;
        }

        const reset_fence_success = c.vkResetFences(self.device, 1, &self.in_flight_fence[frame_index]);
        if (reset_fence_success != c.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }

        if (c.vkResetCommandBuffer(self.command_buffers[frame_index], 0) != c.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }

        try record_command_buffer(self, self.command_buffers[frame_index], image_index, buffers, vertex_count);

        // TODO Not sure if it makes sense to place this here or in the record_command_buffer call
        const end_recording_success = c.vkEndCommandBuffer(self.command_buffers[frame_index]);
        if (end_recording_success != c.VK_SUCCESS) {
            return VkAbstractionError.EndRecordingFailure;
        }

        //const wait_semaphores = [_]c.VkSemaphore{
        //    instance.image_available_semaphore,
        //};

        const wait_stages = [_]c.VkPipelineStageFlags{
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        };

        //const signal_semaphores: []c.VkSemaphore = .{instance.image_completion_semaphore};

        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1, //wait_semaphores.len,
            .pWaitSemaphores = &self.image_available_semaphore[frame_index], //wait_semaphores.ptr,
            .pWaitDstStageMask = &wait_stages,
            .signalSemaphoreCount = 1, //signal_semaphores.len,
            .pSignalSemaphores = &self.image_completion_semaphore[frame_index], //signal_semaphores.ptr,
            .commandBufferCount = 1,
            .pCommandBuffers = &self.command_buffers[frame_index],
        };

        const queue_submit_success = c.vkQueueSubmit(self.present_queue, 1, &submit_info, self.in_flight_fence[frame_index]);
        if (queue_submit_success != c.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }

        //const swapchains = []c.VkSwapchainKHR{instance.swapchain};

        const present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.image_completion_semaphore[frame_index],
            .swapchainCount = 1,
            .pSwapchains = &self.swapchain, //swapchains,
            .pImageIndices = &image_index,
        };

        const present_success = c.vkQueuePresentKHR(self.present_queue, &present_info);
        if (present_success != c.VK_SUCCESS) {
            return VkAbstractionError.PresentationFailure;
        }
    }

    fn cleanup_swapchain(self: *Instance) void {
        for (self.frame_buffers) |i| {
            c.vkDestroyFramebuffer(self.device, i, null);
        }
        self.allocator.*.free(self.frame_buffers);

        for (self.swapchain_image_views) |image_view| {
            c.vkDestroyImageView(self.device, image_view, null);
        }
        self.allocator.*.free(self.swapchain_image_views);
        c.vkDestroySwapchainKHR(self.device, self.swapchain, null);
        self.allocator.*.free(self.swapchain_images);
    }

    pub fn recreate_swapchain(self: *Instance) VkAbstractionError!void {
        var width: i32 = 0;
        var height: i32 = 0;
        c.glfwGetFramebufferSize(self.window, &width, &height);
        while (width == 0 or height == 0) {
            c.glfwGetFramebufferSize(self.window, &width, &height);
            c.glfwWaitEvents();
        }

        _ = c.vkDeviceWaitIdle(self.device);

        cleanup_swapchain(self);

        try create_swapchain(self);
        try create_swapchain_image_views(self);
        try create_framebuffers(self);
    }

    /// This should be called before the end of the main loop so all zig allocations can be deferred
    /// Free all of our vulkan state
    pub fn cleanup(self: *Instance) void {
        for (0..self.MAX_CONCURRENT_FRAMES) |i| {
            c.vkDestroySemaphore(self.device, self.image_available_semaphore[i], null);
            c.vkDestroySemaphore(self.device, self.image_completion_semaphore[i], null);
            c.vkDestroyFence(self.device, self.in_flight_fence[i], null);
        }

        c.vkFreeCommandBuffers(self.device, self.command_pool, self.MAX_CONCURRENT_FRAMES, self.command_buffers.ptr);
        self.allocator.free(self.command_buffers);

        c.vkDestroyCommandPool(self.device, self.command_pool, null);

        cleanup_swapchain(self);

        c.vkDestroyPipeline(self.device, self.graphics_pipeline, null);
        c.vkDestroyRenderPass(self.device, self.renderpass, null);
        c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);

        for (0..self.shader_modules.items.len) |i| {
            c.vkDestroyShaderModule(self.device, self.shader_modules.items[i], null);
        }
        self.shader_modules.deinit();

        c.vkDestroySurfaceKHR(self.vk_instance, self.surface, null);
        c.vkDestroyDevice(self.device, null);
        c.vkDestroyInstance(self.vk_instance, null);
        c.glfwDestroyWindow(self.window);
        c.glfwTerminate();
    }
};

pub fn glfw_error_callback(code: c_int, description: [*c]const u8) callconv(.C) void {
    std.debug.print("[Error] [GLFW] {} {s}\n", .{ code, description });
}
