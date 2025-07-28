const std = @import("std");
const c = @import("clibs.zig");
const zm = @import("zmath");
const main = @import("main.zig");
const chunk = @import("chunk.zig");
const mesh_generation = @import("mesh_generation.zig");
const physics = @import("physics.zig");

// TODO There has got to be a better way than this, so much smell...
const chunk_vert_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/simple.vert.spv")))));
const chunk_frag_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/simple.frag.spv")))));

const outline_vert_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/outline.vert.spv")))));
const outline_frag_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/outline.frag.spv")))));

const cursor_vert_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/cursor.vert.spv")))));
const cursor_frag_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/cursor.frag.spv")))));

const block_selection_cube: [17]Vertex = .{
    //front
    .{.pos = .{-0.001,-0.001,-0.001}, .color = .{1.0,1.0,1.0} },
    .{.pos = .{1.001,-0.001,-0.001}, .color = .{1.0,1.0,1.0} },
    .{.pos = .{1.001,1.001,-0.001}, .color = .{1.0,1.0,1.0} },
    .{.pos = .{-0.001,1.001,-0.001}, .color = .{1.0,1.0,1.0} },
    //left
    .{.pos = .{-0.001,-0.001,-0.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,-0.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,1.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,1.001,-0.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,-0.001,-0.001}, .color = .{1.0,1.0,1.0}},
    //right
    .{.pos = .{1.001,-0.001,-0.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{1.001,-0.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{1.001,1.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{1.001,1.001,-0.001}, .color = .{1.0,1.0,1.0}},
    //back
    .{.pos = .{1.001,1.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,1.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,-0.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{1.001,-0.001,1.001}, .color = .{1.0,1.0,1.0}},
};

const cursor_vertices: [6]Vertex = .{
    .{.pos = .{-0.03125,-0.03125,0.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.03125,0.03125,0.0}, .color = .{1.0,1.0,0.0}},
    .{.pos = .{-0.03125,0.03125,0.0}, .color = .{0.0,1.0,0.0}},
    .{.pos = .{-0.03125,-0.03125,0.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.03125,-0.03125,0.0}, .color = .{1.0,0.0,0.0}},
    .{.pos = .{0.03215,0.03125,0.0}, .color = .{1.0,1.0,0.0}},
};

// Attempt at descriptive Errors
pub const VkAbstractionError = error{
    Success,
    OutOfMemory,
    GLFWInitializationFailed,
    GLFWErrorCallbackFailure,
    NullWindow,
    RequiredExtensionsFailure,
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
    DescriptorSetCreationFailure,
    DeviceBufferAllocationFailure,
    DeviceBufferBindFailure,
    DescriptorPoolCreationFailed,
    SuitableDeviceMemoryTypeSelectionFailure,
    DepthFormatAvailablityFailure,
    DepthResourceCreationFailure,
    VertexBufferCreationFailure,
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
    pos: @Vector(3, f32),
    color: @Vector(3, f32),
};

pub const ChunkVertex = packed struct {
    index: u32,
    uv: @Vector(2, f32), // TODO Make the UV split into a texture index and the normal values (we can do basic lighting and have access to all textures using a texture atlas essentially with the same amount of data)
    pos: @Vector(3, f32), // 3 * u5 + 1 bit
};

const ChunkRenderData = struct {
    size: @Vector(3, u32),
    pos: @Vector(3, f32),
    model: zm.Mat = zm.identity(),
};

/// image_views size should be of size MAX_CONCURRENT_FRAMES
/// Current implementation also assumes 2D texture
/// Defaults to 2D image view type
/// Defaults to RGBA SRGB format
pub const ImageInfo = struct{
    data: *c.stbi_uc = undefined,
    width: i32 = undefined,
    height: i32 = undefined,
    depth: i32 = undefined,
    channels: i32 = undefined,
    format: c.VkFormat = c.VK_FORMAT_R8G8B8A8_SRGB,
    view_type: c.VkImageViewType = c.VK_IMAGE_VIEW_TYPE_2D,
    image: c.VkImage = undefined,
    alloc: c.VmaAllocation = undefined,
    subresource_range: c.VkImageSubresourceRange = undefined,
    views: []c.VkImageView = undefined,
    samplers: []c.VkSampler = undefined,
};

/// All the info required to render a vertex buffer
pub const RenderInfo = struct {
    vertex_index: u32,
    pipeline_index: u32,
    vertex_count: u32 = 0,
    vertex_buffer_offset: c.VkDeviceSize = 0,
    vertex_render_offset: u32 = 0,
    rendering_enabled: bool = true,
};

// The vulkan/render state
pub const VulkanState = struct {
    REQUIRE_FAMILIES: u32 = c.VK_QUEUE_GRAPHICS_BIT,
    MAX_CONCURRENT_FRAMES: u32,

    ENGINE_NAME: *const [10:0]u8,

    allocator: *const std.mem.Allocator,

    vma_allocator: c.VmaAllocator = undefined,

    vk_instance: c.VkInstance = undefined,
    window: *c.GLFWwindow = undefined,
    surface: c.VkSurfaceKHR = undefined,

    physical_device: c.VkPhysicalDevice = undefined,
    physical_device_properties: c.VkPhysicalDeviceProperties = undefined,
    mem_properties: c.VkPhysicalDeviceMemoryProperties = undefined,

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

    descriptor_pool : c.VkDescriptorPool = undefined,
    descriptor_sets : []c.VkDescriptorSet = undefined,
    descriptor_set_layout : c.VkDescriptorSetLayout = undefined,

    pipeline_layout: c.VkPipelineLayout = undefined,
    renderpass: c.VkRenderPass = undefined,
    pipelines: []c.VkPipeline = undefined,
    frame_buffers: []c.VkFramebuffer = undefined,
    
    render_targets: std.ArrayList(RenderInfo) = undefined,

    vertex_buffers: std.ArrayList(c.VkBuffer) = undefined,
    vertex_allocs: std.ArrayList(c.VmaAllocation) = undefined,

    ubo_buffers: std.ArrayList(c.VkBuffer) = undefined,
    ubo_allocs: std.ArrayList(c.VmaAllocation) = undefined,
    
    ssbo_buffers: std.ArrayList(c.VkBuffer) = undefined,
    ssbo_allocs: std.ArrayList(c.VmaAllocation) = undefined,

    images: []ImageInfo = undefined,

    command_pool: c.VkCommandPool = undefined,
    command_buffers: []c.VkCommandBuffer = undefined,

    image_available_semaphores: []c.VkSemaphore = undefined,
    image_completion_semaphores: []c.VkSemaphore = undefined,
    in_flight_fences: []c.VkFence = undefined,

    depth_format: c.VkFormat = undefined,
    depth_image: c.VkImage = undefined,
    depth_image_alloc: c.VmaAllocation = undefined,
    depth_image_view: c.VkImageView = undefined,

    PUSH_CONSTANT_SIZE: u32,
    push_constant_data: []u8 = undefined,
    push_constant_info: c.VkPushConstantRange = undefined,

    // TODO move the GLFW code out and make this a vulkan only function
    /// Creates our Vulkan instance and GLFW window
    pub fn window_setup(self: *VulkanState, application_name: []const u8, engine_name: []const u8) VkAbstractionError!void {
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

        self.window = c.glfwCreateWindow(800, 600, application_name.ptr, null, null) orelse return VkAbstractionError.NullWindow;

        const application_info = c.VkApplicationInfo{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = application_name.ptr,
            .pEngineName = engine_name.ptr,
            .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = c.VK_API_VERSION_1_2,
        };

        std.debug.print("[Info] Vulkan Application Info:\n", .{});
        std.debug.print("\tApplication name: {s}\n", .{application_info.pApplicationName});
        std.debug.print("\tEngine name: {s}\n", .{application_info.pEngineName});

        var required_extension_count: u32 = 0;
        const required_extensions = c.glfwGetRequiredInstanceExtensions(&required_extension_count) orelse return VkAbstractionError.RequiredExtensionsFailure;

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
            .enabledLayerCount = if (std.debug.runtime_safety) @intCast(validation_layers.len) else 0,
            .ppEnabledLayerNames = if (std.debug.runtime_safety) &validation_layers else null,
            .enabledExtensionCount = @intCast(extensions_arraylist.items.len),
            .ppEnabledExtensionNames = extensions_arraylist.items.ptr,
        };

        const instance_result = c.vkCreateInstance(&create_info, null, &self.vk_instance);

        if (instance_result != c.VK_SUCCESS) {
            std.debug.print("[Error] Vk Instance Creation Failed: {}\n", .{instance_result});
            return VkAbstractionError.VkInstanceCreationFailure;
        }
    }

    pub fn create_surface(self: *VulkanState) VkAbstractionError!void {
        const success = c.glfwCreateWindowSurface(self.vk_instance, self.window, null, &self.surface);

        if (success != c.VK_SUCCESS) {
            std.debug.print("[Error] Surface Creation Failed: {}\n", .{success});
            return VkAbstractionError.SurfaceCreationFailed;
        }
    }

    pub fn pick_physical_device(self: *VulkanState) VkAbstractionError!void {
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
        self.physical_device_properties = device_properties;

        std.debug.print("[Info] API version: {any}\n[Info] Driver version: {any}\n[Info] Device name: {s}\n", .{ device_properties.apiVersion, device_properties.driverVersion, device_properties.deviceName });

        // TODO Check for device extension compatibility
    }

    pub fn create_present_queue(self: *VulkanState, flags: u32) VkAbstractionError!void {
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
        const device_features = c.VkPhysicalDeviceFeatures{
            .samplerAnisotropy = c.VK_TRUE,
            .fillModeNonSolid = c.VK_TRUE,
            .wideLines = c.VK_TRUE,
        };

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

    pub fn create_swapchain(self: *VulkanState) VkAbstractionError!void {
        const support = try query_swapchain_support(self);
        defer self.allocator.*.free(support.formats);
        defer self.allocator.*.free(support.present_modes);

        //if (support.present_size > 0 and support.formats_size > 0) {
        var surface_format: c.VkSurfaceFormatKHR = support.formats[0];
        // TODO Come up with a solution for why adding 1 to the image count causes a serious memory leak (Nvidia Linux Proprietary driver only?)...
        // Time between frames significantly decreases when allocating at least one more image than the minimum on some systems
        std.debug.print("[Info] Swapchain minimum image count: {}\n", .{support.capabilities.minImageCount});
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
        }
        
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

    pub fn create_swapchain_image_views(self: *VulkanState) VkAbstractionError!void {
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

    pub fn create_descriptor_pool(self : *VulkanState) VkAbstractionError!void {
        const ubo_pool_size = c.VkDescriptorPoolSize{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 10,
        };
        
        const storage_pool_size = c.VkDescriptorPoolSize{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 10,
        };
        
        const image_pool_size = c.VkDescriptorPoolSize{
            .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 10,
        };

        const pool_sizes : [3]c.VkDescriptorPoolSize = .{ubo_pool_size, storage_pool_size, image_pool_size};

        const pool_info = c.VkDescriptorPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .poolSizeCount = pool_sizes.len,
            .pPoolSizes = &pool_sizes,
            .maxSets = self.MAX_CONCURRENT_FRAMES,
            .flags = c.VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT,
        };
        
        const success = c.vkCreateDescriptorPool(self.device, &pool_info, null, &self.descriptor_pool);
        if (success != c.VK_SUCCESS)
        {
            std.debug.print("[Error] Unable to create Descriptor Pool: {}\n", .{success});
            return VkAbstractionError.DescriptorPoolCreationFailed;
        }
    }

    pub fn create_descriptor_set_layouts(self : *VulkanState) VkAbstractionError!void
    {
        // A description of the bindings and their contents
        // Essentially we need one of these per uniform buffer
        const layout_bindings: [4]c.VkDescriptorSetLayoutBinding = .{
            c.VkDescriptorSetLayoutBinding{
                .binding = 0,
                .descriptorCount = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .stageFlags = c.VK_SHADER_STAGE_ALL,//c.VK_SHADER_STAGE_VERTEX_BIT,
                .pImmutableSamplers = null,
            },
            c.VkDescriptorSetLayoutBinding{
                .binding = 1,
                .descriptorCount = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .stageFlags = c.VK_SHADER_STAGE_ALL,//c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .pImmutableSamplers = null,
            },
            c.VkDescriptorSetLayoutBinding{
                .binding = 2,
                .descriptorCount = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .stageFlags = c.VK_SHADER_STAGE_ALL,//c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .pImmutableSamplers = null,
            },
            c.VkDescriptorSetLayoutBinding{
                .binding = 3,
                .descriptorCount = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .stageFlags = c.VK_SHADER_STAGE_ALL,
                .pImmutableSamplers = null,
            },
        };

        const layout_info = c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = @intCast(layout_bindings.len),
            .pBindings = &layout_bindings,
        };

        const descriptor_set_success = c.vkCreateDescriptorSetLayout(self.device, &layout_info, null, &self.descriptor_set_layout);
        if (descriptor_set_success != c.VK_SUCCESS) {
            std.debug.print("[Error] Unable to create descriptor set: {}\n", .{descriptor_set_success});
            return VkAbstractionError.DescriptorSetCreationFailure;
        }
    }

    pub fn create_generic_pipeline(self: *VulkanState, vert_source: []align(4) u8, frag_source: []align(4) u8, wireframe: bool) VkAbstractionError!c.VkPipeline {
        const vert_index = self.shader_modules.items.len;
        try create_shader_module(self, vert_source);
        const frag_index = self.shader_modules.items.len;
        try create_shader_module(self, frag_source);


        const vertex_shader_stage = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = self.shader_modules.items[vert_index],
            .pName = "main",
        };

        const fragment_shader_stage = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = self.shader_modules.items[frag_index],
            .pName = "main",
        };

        const shader_stages: [2]c.VkPipelineShaderStageCreateInfo = .{vertex_shader_stage, fragment_shader_stage};

        const dynamic_state = [_]c.VkDynamicState{
            c.VK_DYNAMIC_STATE_VIEWPORT,
            c.VK_DYNAMIC_STATE_SCISSOR,
        };

        const dynamic_state_create_info = c.VkPipelineDynamicStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamic_state.len,
            .pDynamicStates = &dynamic_state,
        };

        var binding_description: [1]c.VkVertexInputBindingDescription = .{ 
            c.VkVertexInputBindingDescription{
                .binding = 0,
                .stride = @sizeOf(Vertex),
                .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
            }
        };

        var attribute_description: []c.VkVertexInputAttributeDescription = undefined;
        attribute_description = try self.allocator.*.alloc(c.VkVertexInputAttributeDescription, 2);
        defer self.allocator.*.free(attribute_description);
        attribute_description[0] = .{ .binding = 0, .location = 0, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = 0 };
        attribute_description[1] = .{ .binding = 0, .location = 1, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = @sizeOf(@Vector(3, f32)) };

        const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = @intCast(binding_description.len),
            .pVertexBindingDescriptions = &binding_description,
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
            .polygonMode = if (wireframe) c.VK_POLYGON_MODE_LINE else c.VK_POLYGON_MODE_FILL,
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

        const depth_stencil_state_info = c.VkPipelineDepthStencilStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable = c.VK_TRUE,
            .depthWriteEnable = c.VK_TRUE,
            .depthCompareOp = c.VK_COMPARE_OP_LESS,
            .depthBoundsTestEnable = c.VK_FALSE,
            .minDepthBounds = 0.0,
            .maxDepthBounds = 1.0,
            .stencilTestEnable = c.VK_FALSE,
        };

        const pipeline_create_info = c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount = @intCast(shader_stages.len),
            .pStages = &shader_stages,
            .pVertexInputState = &vertex_input_info,
            .pInputAssemblyState = &assembly_create_info,
            .pViewportState = &viewport_create_info,
            .pRasterizationState = &rasterization_create_info,
            .pMultisampleState = &multisampling_create_info,
            .pDepthStencilState = &depth_stencil_state_info,
            .pColorBlendState = &color_blending_create_info,
            .pDynamicState = &dynamic_state_create_info,
            .layout = self.pipeline_layout,
            .renderPass = self.renderpass,
            .subpass = 0,
        };

        var pipeline: c.VkPipeline = undefined;
        const pipeline_success = c.vkCreateGraphicsPipelines(self.device, null, 1, &pipeline_create_info, null, &pipeline);
        if (pipeline_success != c.VK_SUCCESS) {
            return VkAbstractionError.FailedCreatingGraphicsPipeline;
        }

        return pipeline;
    }

    pub fn create_outline_pipeline(self: *VulkanState, vert_source: []align(4) u8, frag_source: []align(4) u8) VkAbstractionError!c.VkPipeline {
        const vert_index = self.shader_modules.items.len;
        try create_shader_module(self, vert_source);
        const frag_index = self.shader_modules.items.len;
        try create_shader_module(self, frag_source);

        const vertex_shader_stage = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = self.shader_modules.items[vert_index],
            .pName = "main",
        };

        const fragment_shader_stage = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = self.shader_modules.items[frag_index],
            .pName = "main",
        };

        const shader_stages: [2]c.VkPipelineShaderStageCreateInfo = .{vertex_shader_stage, fragment_shader_stage};

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
        defer self.allocator.*.free(binding_description);
        binding_description[0] = .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        var attribute_description: []c.VkVertexInputAttributeDescription = undefined;
        attribute_description = try self.allocator.*.alloc(c.VkVertexInputAttributeDescription, 2);
        defer self.allocator.*.free(attribute_description);
        attribute_description[0] = .{ .binding = 0, .location = 0, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = 0 };
        attribute_description[1] = .{ .binding = 0, .location = 1, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = @sizeOf(@Vector(3, f32)) };

        const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = @intCast(binding_description.len),
            .pVertexBindingDescriptions = binding_description.ptr,
            .vertexAttributeDescriptionCount = @intCast(attribute_description.len),
            .pVertexAttributeDescriptions = attribute_description.ptr,
        };

        const assembly_create_info = c.VkPipelineInputAssemblyStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_LINE_STRIP,
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
            .polygonMode = c.VK_POLYGON_MODE_LINE,
            .lineWidth = 2.0,
            .cullMode = c.VK_CULL_MODE_NONE,
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

        const depth_stencil_state_info = c.VkPipelineDepthStencilStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable = c.VK_TRUE,
            .depthWriteEnable = c.VK_TRUE,
            .depthCompareOp = c.VK_COMPARE_OP_LESS,
            .depthBoundsTestEnable = c.VK_FALSE,
            .minDepthBounds = 0.0,
            .maxDepthBounds = 1.0,
            .stencilTestEnable = c.VK_FALSE,
        };

        const pipeline_create_info = c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount = @intCast(shader_stages.len),
            .pStages = &shader_stages,
            .pVertexInputState = &vertex_input_info,
            .pInputAssemblyState = &assembly_create_info,
            .pViewportState = &viewport_create_info,
            .pRasterizationState = &rasterization_create_info,
            .pMultisampleState = &multisampling_create_info,
            .pDepthStencilState = &depth_stencil_state_info,
            .pColorBlendState = &color_blending_create_info,
            .pDynamicState = &dynamic_state_create_info,
            .layout = self.pipeline_layout,
            .renderPass = self.renderpass,
            .subpass = 0,
        };

        var pipeline: c.VkPipeline = undefined;
        const pipeline_success = c.vkCreateGraphicsPipelines(self.device, null, 1, &pipeline_create_info, null, &pipeline);
        if (pipeline_success != c.VK_SUCCESS) {
            return VkAbstractionError.FailedCreatingGraphicsPipeline;
        }

        return pipeline;
    }

    /// Creates a shader module and appends the handler to the state's shader array list
    pub fn create_shader_module(self: *VulkanState, file_source : [] const align(4) u8) VkAbstractionError!void {
        var shader_module: c.VkShaderModule = undefined;

        const create_info = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            // Size of the source in bytes not u32
            .codeSize = file_source.len,
            // This must be aligned to 4 bytes
            .pCode = @alignCast(@ptrCast(file_source.ptr)),
        };

        const create_shader_module_success = c.vkCreateShaderModule(self.device, &create_info, null, &shader_module);
        if (create_shader_module_success != c.VK_SUCCESS) {
            return VkAbstractionError.CreateShaderModuleFailed;
        }

        try self.shader_modules.append(shader_module);
    }

    pub fn create_framebuffers(self: *VulkanState) VkAbstractionError!void {
        self.frame_buffers = try self.allocator.*.alloc(c.VkFramebuffer, self.swapchain_image_views.len);

        for (self.swapchain_image_views, 0..self.swapchain_image_views.len) |image_view, i| {

            const attachments: [2]c.VkImageView = .{ image_view, self.depth_image_view };

            const framebuffer_create_info = c.VkFramebufferCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass = self.renderpass,
                .attachmentCount = attachments.len,
                .pAttachments = &attachments,
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

    pub fn create_command_pool(self: *VulkanState) VkAbstractionError!void {
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

    pub fn create_command_buffers(self: *VulkanState) VkAbstractionError!void {
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

    fn record_command_buffer(self: *VulkanState, command_buffer: c.VkCommandBuffer, render_state: *[]RenderInfo, image_index: u32, frame_index: u32) VkAbstractionError!void {
        _ = &frame_index;

        const begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = 0,
        };

        if (c.vkBeginCommandBuffer(command_buffer, &begin_info) != c.VK_SUCCESS) {
            return VkAbstractionError.BeginRenderPassFailed;
        }

        var clear_colors: [2]c.VkClearValue = undefined;
        clear_colors[0].color.float32 = .{0.0, 0.003, 0.0005, 0.0};
        clear_colors[1].depthStencil = .{ .depth = 1.0, .stencil = 0 };

        const render_pass_info = c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = self.renderpass,
            .framebuffer = self.frame_buffers[image_index],
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swapchain_extent,
            },
            .clearValueCount = clear_colors.len,
            .pClearValues = &clear_colors,
        };

        c.vkCmdBeginRenderPass(command_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);

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
        
        // Camera
        c.vkCmdPushConstants(command_buffer, self.pipeline_layout, c.VK_SHADER_STAGE_ALL, 0, self.push_constant_info.size, &self.push_constant_data[0]);
        c.vkCmdBindDescriptorSets(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, &self.descriptor_sets[frame_index], 0, null);

        var previous_pipeline_index: u32 = std.math.maxInt(u32);
        for (render_state.*) |target| {
            if (target.rendering_enabled) {
                const pipeline_index = target.pipeline_index;
                if (pipeline_index != previous_pipeline_index) {
                    c.vkCmdBindPipeline(
                        command_buffer,
                        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                        self.pipelines[pipeline_index]
                        );
                    previous_pipeline_index = pipeline_index;
                }
                
                c.vkCmdBindVertexBuffers(
                    command_buffer,
                    0,
                    1,
                    &self.vertex_buffers.items[target.vertex_index],
                    &target.vertex_buffer_offset
                    );
                
                c.vkCmdDraw(command_buffer, target.vertex_count, 1, 0, 0);
            }
        }

        c.vkCmdEndRenderPass(command_buffer);
    }

    pub fn create_pipeline_layout(self: *VulkanState) VkAbstractionError!void {
        const pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 1,
            .pSetLayouts = &self.descriptor_set_layout,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &self.push_constant_info,
        };

        const pipeline_layout_success = c.vkCreatePipelineLayout(self.device, &pipeline_layout_create_info, null, &self.pipeline_layout);

        if (pipeline_layout_success != c.VK_SUCCESS) {
            return VkAbstractionError.CreatePipelineLayoutFailed;
        }
    }

    pub fn create_simple_chunk_pipeline(self: *VulkanState, vert_source: []align(4) u8, frag_source: []align(4) u8, wireframe: bool) VkAbstractionError!c.VkPipeline {
        const vert_index = self.shader_modules.items.len;
        try create_shader_module(self, vert_source);
        const frag_index = self.shader_modules.items.len;
        try create_shader_module(self, frag_source);


        const vertex_shader_stage = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = self.shader_modules.items[vert_index],
            .pName = "main",
        };

        const fragment_shader_stage = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = self.shader_modules.items[frag_index],
            .pName = "main",
        };

        const shader_stages: [2]c.VkPipelineShaderStageCreateInfo = .{vertex_shader_stage, fragment_shader_stage};

        const dynamic_state = [_]c.VkDynamicState{
            c.VK_DYNAMIC_STATE_VIEWPORT,
            c.VK_DYNAMIC_STATE_SCISSOR,
        };

        const dynamic_state_create_info = c.VkPipelineDynamicStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamic_state.len,
            .pDynamicStates = &dynamic_state,
        };

        const binding_description: [1]c.VkVertexInputBindingDescription = .{
            c.VkVertexInputBindingDescription{
                .binding = 0,
                .stride = @sizeOf(ChunkVertex),
                .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
            },
        };

        const attribute_description: [3]c.VkVertexInputAttributeDescription = .{ 
            c.VkVertexInputAttributeDescription{ .binding = 0, .location = 0, .format = c.VK_FORMAT_R32_UINT, .offset = 0 }, // chunk index
            c.VkVertexInputAttributeDescription{ .binding = 0, .location = 1, .format = c.VK_FORMAT_R32G32_SFLOAT, .offset = @sizeOf(u32) }, // uv
            c.VkVertexInputAttributeDescription{ .binding = 0, .location = 2, .format = c.VK_FORMAT_R32G32B32_SFLOAT, .offset = @sizeOf(u32) + @sizeOf(@Vector(2, f32)) }, // pos
        };

        const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = @intCast(binding_description.len),
            .pVertexBindingDescriptions = &binding_description,
            .vertexAttributeDescriptionCount = @intCast(attribute_description.len),
            .pVertexAttributeDescriptions = &attribute_description,
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
            .polygonMode = if (wireframe) c.VK_POLYGON_MODE_LINE else c.VK_POLYGON_MODE_FILL,
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

        const depth_stencil_state_info = c.VkPipelineDepthStencilStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable = c.VK_TRUE,
            .depthWriteEnable = c.VK_TRUE,
            .depthCompareOp = c.VK_COMPARE_OP_LESS,
            .depthBoundsTestEnable = c.VK_FALSE,
            .minDepthBounds = 0.0,
            .maxDepthBounds = 1.0,
            .stencilTestEnable = c.VK_FALSE,
        };

        const pipeline_create_info = c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount = @intCast(shader_stages.len),
            .pStages = &shader_stages,
            .pVertexInputState = &vertex_input_info,
            .pInputAssemblyState = &assembly_create_info,
            .pViewportState = &viewport_create_info,
            .pRasterizationState = &rasterization_create_info,
            .pMultisampleState = &multisampling_create_info,
            .pDepthStencilState = &depth_stencil_state_info,
            .pColorBlendState = &color_blending_create_info,
            .pDynamicState = &dynamic_state_create_info,
            .layout = self.pipeline_layout,
            .renderPass = self.renderpass,
            .subpass = 0,
        };

        var pipeline: c.VkPipeline = undefined;
        const pipeline_success = c.vkCreateGraphicsPipelines(self.device, null, 1, &pipeline_create_info, null, &pipeline);
        if (pipeline_success != c.VK_SUCCESS) {
            return VkAbstractionError.FailedCreatingGraphicsPipeline;
        }

        return pipeline;
    }

    pub fn create_render_pass(self: *VulkanState) VkAbstractionError!void {
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
        
        const depth_attachment = c.VkAttachmentDescription{
            .format = self.depth_format,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };

        const depth_attachment_ref = c.VkAttachmentReference{
            .attachment = 1,
            .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };
        
        const subpass = c.VkSubpassDescription{
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = 1,
            .pColorAttachments = &color_attachment_ref,
            .pDepthStencilAttachment = &depth_attachment_ref,
        };

        const attachments: [2]c.VkAttachmentDescription = .{ color_attachment, depth_attachment };

        // Ensure the renderpass is waiting for our frames to complete
        const subpass_dependency = c.VkSubpassDependency{
            .srcSubpass = c.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .srcAccessMask = 0,
            .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        };

        const renderpass_create_info = c.VkRenderPassCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = attachments.len,
            .pAttachments = &attachments,
            .subpassCount = 1,
            .pSubpasses = &subpass,
            .dependencyCount = 1,
            .pDependencies = &subpass_dependency,
        };

        const render_pass_creation = c.vkCreateRenderPass(self.device, &renderpass_create_info, null, &self.renderpass);
        if (render_pass_creation != c.VK_SUCCESS) {
            return VkAbstractionError.FailedCreatingRenderPass;
        }
    }

    pub fn create_sync_objects(self: *VulkanState) VkAbstractionError!void {
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
            const success_a = c.vkCreateSemaphore(self.device, &image_available_semaphore_info, null, &self.image_available_semaphores[i]);
            const success_b = c.vkCreateSemaphore(self.device, &image_completion_semaphore_info, null, &self.image_completion_semaphores[i]);
            const success_c = c.vkCreateFence(self.device, &in_flight_fence_info, null, &self.in_flight_fences[i]);

            if (success_a != c.VK_SUCCESS or success_b != c.VK_SUCCESS or success_c != c.VK_SUCCESS) {
                return VkAbstractionError.CreateSyncObjectsFailed;
            }
        }
    }

    pub fn draw_frame(self: *VulkanState, frame_index: u32, render_state: *[]RenderInfo) VkAbstractionError!void {
        const fence_wait = c.vkWaitForFences(self.device, 1, &self.in_flight_fences[frame_index], c.VK_TRUE, std.math.maxInt(u64));
        if (fence_wait != c.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }
        
        var image_index: u32 = 0;
        const acquire_next_image_success = c.vkAcquireNextImageKHR(self.device, self.swapchain, std.math.maxInt(u64), self.image_available_semaphores[frame_index], null, &image_index);

        if (acquire_next_image_success == c.VK_ERROR_OUT_OF_DATE_KHR or acquire_next_image_success == c.VK_SUBOPTIMAL_KHR or self.framebuffer_resized) {
            try recreate_swapchain(self);
            self.framebuffer_resized = false;
            return;
        } else if (acquire_next_image_success != c.VK_SUCCESS) {
            std.debug.print("[Error] Unable to acquire next swapchain image: {} \n", .{acquire_next_image_success});
            return VkAbstractionError.AcquireNextSwapchainImageFailed;
        }
        
        const reset_fence_success = c.vkResetFences(self.device, 1, &self.in_flight_fences[frame_index]);
        if (reset_fence_success != c.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }

        if (c.vkResetCommandBuffer(self.command_buffers[frame_index], 0) != c.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }

        try record_command_buffer(self, self.command_buffers[frame_index], render_state, image_index, frame_index);

        const end_recording_success = c.vkEndCommandBuffer(self.command_buffers[frame_index]);
        if (end_recording_success != c.VK_SUCCESS) {
            return VkAbstractionError.EndRecordingFailure;
        }

        const wait_stages = [_]c.VkPipelineStageFlags{
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            //c.VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT,
        };

        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.image_available_semaphores[frame_index],
            .pWaitDstStageMask = &wait_stages,
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &self.image_completion_semaphores[frame_index],
            .commandBufferCount = 1,
            .pCommandBuffers = &self.command_buffers[frame_index],
        };

        const queue_submit_success = c.vkQueueSubmit(self.present_queue, 1, &submit_info, self.in_flight_fences[frame_index]);
        if (queue_submit_success != c.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }

        const present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.image_completion_semaphores[frame_index],
            .swapchainCount = 1,
            .pSwapchains = &self.swapchain,
            .pImageIndices = &image_index,
        };

        const present_success = c.vkQueuePresentKHR(self.present_queue, &present_info);
        if (present_success == c.VK_SUBOPTIMAL_KHR or present_success == c.VK_ERROR_OUT_OF_DATE_KHR or self.framebuffer_resized)
        {
            try recreate_swapchain(self);
            self.framebuffer_resized = false;
            return;
        } else if (present_success != c.VK_SUCCESS) {
            std.debug.print("[Error] Presentation failure: {} \n", .{present_success});
            return VkAbstractionError.PresentationFailure;
        }
    }

    /// Image format does not matter
    pub fn create_depth_resources(self: *VulkanState) VkAbstractionError!void
    {
        const candidates: [3]c.VkFormat = .{c.VK_FORMAT_D32_SFLOAT, c.VK_FORMAT_D32_SFLOAT_S8_UINT, c.VK_FORMAT_D24_UNORM_S8_UINT};
        const format = try self.depth_texture_format(&candidates, c.VK_IMAGE_TILING_OPTIMAL, c.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT);
        self.depth_format = format;

        const image_create_info = c.VkImageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = c.VK_IMAGE_TYPE_2D,
            .extent = .{ .width = self.swapchain_extent.width, .height = self.swapchain_extent.height, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .format = format,
            .tiling = c.VK_IMAGE_TILING_OPTIMAL,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        };

        const alloc_info = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_AUTO,
            .flags = c.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
            .priority = 1.0,
        };

        const subresource_range = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        };

        const depth_image_creation_success = c.vmaCreateImage(self.vma_allocator, &image_create_info, &alloc_info, &self.depth_image, &self.depth_image_alloc, null);
        if (depth_image_creation_success != c.VK_SUCCESS)
        {
            return VkAbstractionError.DepthResourceCreationFailure;
        }

        const view_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = self.depth_image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = format,
            .subresourceRange = subresource_range,
        };

        const success = c.vkCreateImageView(self.device, &view_info, null, &self.depth_image_view);
        if (success != c.VK_SUCCESS)
        {
            std.debug.print("Failed to create texture image view: {}\n", .{success}); return;
        }
    }

    fn depth_texture_format(self: *VulkanState, candidates: []const c.VkFormat, tiling: c.VkImageTiling, features: c.VkFormatFeatureFlags) VkAbstractionError!c.VkFormat
    {
        for (candidates) |format|
        {
            var properties : c.VkFormatProperties = undefined;
            c.vkGetPhysicalDeviceFormatProperties(self.physical_device, format, &properties);
    
            if (tiling == c.VK_IMAGE_TILING_LINEAR and (properties.linearTilingFeatures & features) == features)
            {
                return format;
            }
            else if (tiling == c.VK_IMAGE_TILING_OPTIMAL and (properties.optimalTilingFeatures & features) == features)
            {
                return format;
            }
        }
    
        return VkAbstractionError.DepthFormatAvailablityFailure;
    }

    fn cleanup_swapchain(self: *VulkanState) void {
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

    pub fn recreate_swapchain(self: *VulkanState) VkAbstractionError!void {
        var width: i32 = 0;
        var height: i32 = 0;
        c.glfwGetFramebufferSize(self.window, &width, &height);
        while (width == 0 or height == 0) {
            c.glfwGetFramebufferSize(self.window, &width, &height);
            c.glfwWaitEvents();
        }

        _ = c.vkDeviceWaitIdle(self.device);

        cleanup_depth_resources(self);
        cleanup_swapchain(self);

        try create_swapchain(self);
        try create_swapchain_image_views(self);
        try create_depth_resources(self);
        try create_framebuffers(self);
    }

    pub fn cleanup_depth_resources(self: *VulkanState) void
    {
        c.vkDestroyImageView(self.device, self.depth_image_view, null);
        c.vmaDestroyImage(self.vma_allocator, self.depth_image, self.depth_image_alloc);
    }

    fn copy_data_via_staging_buffer(self: *VulkanState, final_buffer: *c.VkBuffer, size: u32, data: *anyopaque) VkAbstractionError!void
    {
        var staging_buffer : c.VkBuffer = undefined;

        const staging_buffer_info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        };

        const staging_alloc_create_info = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_AUTO,
            .flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        };

        var staging_alloc : c.VmaAllocation = undefined;
        var staging_alloc_info : c.VmaAllocationInfo = undefined;

        _ = c.vmaCreateBuffer(self.vma_allocator, &staging_buffer_info, &staging_alloc_create_info, &staging_buffer, &staging_alloc, &staging_alloc_info);

        _ = c.vmaCopyMemoryToAllocation(self.vma_allocator, data, staging_alloc, 0, size);
        
        const command_buffer_alloc_info = c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandPool = self.command_pool,
            .commandBufferCount = 1,
        };
        var command_buffer : c.VkCommandBuffer = undefined;
        const command_buffer_alloc_success = c.vkAllocateCommandBuffers(self.device, &command_buffer_alloc_info, &command_buffer);
        if (command_buffer_alloc_success != c.VK_SUCCESS)
        {
            std.debug.print("Unable to Allocate command buffer for image staging: {}\n", .{command_buffer_alloc_success});
            return;
        }

        // Copy and proper layout from staging buffer to gpu
        const begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };

        const begin_cmd_buffer = c.vkBeginCommandBuffer(command_buffer, &begin_info);
        if (begin_cmd_buffer != c.VK_SUCCESS)
        {
            return;
        }

        const transfer_barrier = c.VkBufferMemoryBarrier{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .buffer = final_buffer.*,
            .size = size,
            .srcAccessMask = 0,
            .dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
        };

        c.vkCmdPipelineBarrier(command_buffer, c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, c.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 1, &transfer_barrier, 0, null);
        
        const region = c.VkBufferCopy{
            .srcOffset = 0,
            .dstOffset = 0,
            .size = size,
        };

        c.vkCmdCopyBuffer(command_buffer, staging_buffer, final_buffer.*, 1, &region);
        // Optimal shader layout translation
        const buffer_read_barrier = c.VkBufferMemoryBarrier{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
            .dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT,
            .buffer = final_buffer.*,
            .offset = 0,
            .size = size,
        };

        c.vkCmdPipelineBarrier(command_buffer, c.VK_PIPELINE_STAGE_TRANSFER_BIT, c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 1, &buffer_read_barrier, 0, null);

        _ = c.vkEndCommandBuffer(command_buffer);

        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer,
        };

        _ = c.vkQueueSubmit(self.present_queue, 1, &submit_info, null);
        _ = c.vkQueueWaitIdle(self.present_queue);

        c.vkFreeCommandBuffers(self.device, self.command_pool, 1, &command_buffer);

        c.vmaDestroyBuffer(self.vma_allocator, staging_buffer, staging_alloc);
    }
    
    pub fn create_vertex_buffer(self: *VulkanState, render_index: u32, stride_size: u32, size: u32, ptr: *anyopaque) VkAbstractionError!void
    {
        var vertex_buffer : c.VkBuffer = undefined;
        var alloc: c.VmaAllocation = undefined;
    
        var buffer_create_info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        }; 
    
        const alloc_create_info = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_AUTO,
            .flags = c.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
        };
    
        const buffer_success = c.vmaCreateBuffer(self.vma_allocator, &buffer_create_info, &alloc_create_info, &vertex_buffer, &alloc, null);
        
        if (buffer_success != c.VK_SUCCESS)
        {
            std.debug.print("success: {}\n", .{buffer_success});
            return VkAbstractionError.VertexBufferCreationFailure;
        }

        try self.copy_data_via_staging_buffer(&vertex_buffer, size, ptr);

        try self.vertex_buffers.append(vertex_buffer);
        try self.vertex_allocs.append(alloc);
        const vertex_count = size / stride_size;
        self.render_targets.items[render_index].vertex_count = vertex_count;
    }

    pub fn replace_vertex_data(self: *VulkanState, render_index: u32, size: u32, ptr: *anyopaque) VkAbstractionError!void
    {
        // needs to occur asynchronously
        var vertex_buffer : c.VkBuffer = undefined;
        var alloc: c.VmaAllocation = undefined;
    
        var buffer_create_info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        }; 
    
        const alloc_create_info = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_AUTO,
            .flags = c.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
        };
    
        const buffer_success = c.vmaCreateBuffer(self.vma_allocator, &buffer_create_info, &alloc_create_info, &vertex_buffer, &alloc, null);
        
        if (buffer_success != c.VK_SUCCESS)
        {
            std.debug.print("success: {}\n", .{buffer_success});
            return VkAbstractionError.VertexBufferCreationFailure;
        }

        try self.copy_data_via_staging_buffer(&vertex_buffer, size, ptr);

        const old_buffer = self.vertex_buffers.items[self.render_targets.items[render_index].vertex_index];
        const old_alloc = self.vertex_allocs.items[self.render_targets.items[render_index].vertex_index];
        self.vertex_buffers.items[self.render_targets.items[render_index].vertex_index] = vertex_buffer;
        self.vertex_allocs.items[self.render_targets.items[render_index].vertex_index] = alloc;
        
        const vertex_count = size / @sizeOf(Vertex);
        self.render_targets.items[render_index].vertex_count = vertex_count;
        
        c.vmaDestroyBuffer(self.vma_allocator, old_buffer, old_alloc);
    }
    
    // TODO decide whether we want to make this host coherent based on the frequency
    // of chunk data updates
    // TODO make a way to modify the buffer at all, could replace it or change
    // data based on frequency and size...
    pub fn create_ssbo(self: *VulkanState, size: u32, ptr: *anyopaque) VkAbstractionError!void
    {
        var ssbo: c.VkBuffer = undefined;
        var alloc: c.VmaAllocation = undefined;
    
        var buffer_create_info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        }; 
    
        const alloc_create_info = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_AUTO,
            .flags = c.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
        };
    
        const buffer_success = c.vmaCreateBuffer(self.vma_allocator, &buffer_create_info, &alloc_create_info, &ssbo, &alloc, null);
        
        if (buffer_success != c.VK_SUCCESS)
        {
            std.debug.print("success: {}\n", .{buffer_success});
            return VkAbstractionError.VertexBufferCreationFailure;
        }

        try self.copy_data_via_staging_buffer(&ssbo, size, ptr);

        try self.ssbo_buffers.append(ssbo);
        try self.ssbo_allocs.append(alloc);
    }

    /// Frees all Vulkan state
    /// All zig allocations should be deferred to after this function is called
    pub fn cleanup(self: *VulkanState) void {
        for (0..self.ubo_buffers.items.len) |i|
        {
            c.vmaDestroyBuffer(self.vma_allocator, self.ubo_buffers.items[i], self.ubo_allocs.items[i]);
        }

        for (0..self.vertex_buffers.items.len) |i| {
            c.vmaDestroyBuffer(self.vma_allocator, self.vertex_buffers.items[i], self.vertex_allocs.items[i]);
        }
        
        for (0..self.ssbo_buffers.items.len) |i| {
            c.vmaDestroyBuffer(self.vma_allocator, self.ssbo_buffers.items[i], self.ssbo_allocs.items[i]);
        }

        for (0..self.MAX_CONCURRENT_FRAMES) |i| {
            c.vkDestroySemaphore(self.device, self.image_available_semaphores[i], null);
            c.vkDestroySemaphore(self.device, self.image_completion_semaphores[i], null);
            c.vkDestroyFence(self.device, self.in_flight_fences[i], null);
        }

        c.vkFreeCommandBuffers(self.device, self.command_pool, self.MAX_CONCURRENT_FRAMES, self.command_buffers.ptr);

        c.vkDestroyCommandPool(self.device, self.command_pool, null);

        cleanup_depth_resources(self);
        cleanup_swapchain(self);
        
        for (0..self.shader_modules.items.len) |i| {
            c.vkDestroyShaderModule(self.device, self.shader_modules.items[i], null);
        }

        for (0..self.pipelines.len) |i|
        {
            c.vkDestroyPipeline(self.device, self.pipelines[i], null);
        }
        c.vkDestroyRenderPass(self.device, self.renderpass, null);
      
        c.vkDestroyDescriptorPool(self.device, self.descriptor_pool, null);
        
        c.vkDestroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
        
        c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);

        c.vkDestroySurfaceKHR(self.vk_instance, self.surface, null);
        c.vmaDestroyAllocator(self.vma_allocator);
        c.vkDestroyDevice(self.device, null);
        c.vkDestroyInstance(self.vk_instance, null);
        c.glfwDestroyWindow(self.window);
        c.glfwTerminate();
    }
};

/// Image format must be assigned before this function
pub fn create_2d_texture(self: *VulkanState, image_info: *ImageInfo) VkAbstractionError!void
{
        const image_size : u64 = @intCast(image_info.width * image_info.height * 4);
        //Create staging buffer
        
        var staging_buffer : c.VkBuffer = undefined;

        const staging_buffer_info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = image_size,
            .usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        };

        const staging_alloc_create_info = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_AUTO,
            .flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        };

        var staging_alloc : c.VmaAllocation = undefined;
        var staging_alloc_info : c.VmaAllocationInfo = undefined;

        _ = c.vmaCreateBuffer(self.vma_allocator, &staging_buffer_info, &staging_alloc_create_info, &staging_buffer, &staging_alloc, &staging_alloc_info);

        _ = c.vmaCopyMemoryToAllocation(self.vma_allocator, image_info.data, staging_alloc, 0, image_size);

        // Create image and transfer data to allocation

        const image_create_info = c.VkImageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = c.VK_IMAGE_TYPE_2D,
            .extent = .{ .width = @intCast(image_info.width), .height = @intCast(image_info.height), .depth = 1},
            .mipLevels = 1,
            .arrayLayers = 1,
            .format = c.VK_FORMAT_R8G8B8A8_SRGB,
            .tiling = c.VK_IMAGE_TILING_OPTIMAL,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage = c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        };
        std.debug.print("width: {} height: {}\n", .{image_create_info.extent.width, image_create_info.extent.height});

        const alloc_info = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_AUTO,
            .flags = c.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,//c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,//, //| ,
            .priority = 1.0,
        };

        const image_creation = c.vmaCreateImage(self.vma_allocator, &image_create_info, &alloc_info, &image_info.image, &image_info.alloc, null);
        if (image_creation != c.VK_SUCCESS)
        {
            std.debug.print("Image creation failure: {}\n", .{image_creation});
            return;
        }
        
        const command_buffer_alloc_info = c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandPool = self.command_pool,
            .commandBufferCount = 1,
        };
        var command_buffer : c.VkCommandBuffer = undefined;
        const command_buffer_alloc_success = c.vkAllocateCommandBuffers(self.device, &command_buffer_alloc_info, &command_buffer);
        if (command_buffer_alloc_success != c.VK_SUCCESS)
        {
            std.debug.print("Unable to Allocate command buffer for image staging: {}\n", .{command_buffer_alloc_success});
            return;
        }

        // Copy and proper layout from staging buffer to gpu
        const begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };

        const begin_cmd_buffer = c.vkBeginCommandBuffer(command_buffer, &begin_info);
        if (begin_cmd_buffer != c.VK_SUCCESS)
        {
            return;
        }
        
        // Translate to optimal tranfer layout

        const transfer_barrier = c.VkImageMemoryBarrier{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image = image_info.image,
            .subresourceRange = image_info.subresource_range,
            .srcAccessMask = 0,
            .dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
        };

        c.vkCmdPipelineBarrier(command_buffer, c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, c.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &transfer_barrier);
        
        // copy from staging buffer to image gpu destination
        const image_subresource = c.VkImageSubresourceLayers{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        };
        
        const region = c.VkBufferImageCopy{
            .bufferOffset = 0,
            .bufferRowLength = 0,
            .bufferImageHeight = 0,
            .imageSubresource = image_subresource,
            .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
            .imageExtent = .{ .width = @intCast(image_info.width), .height = @intCast(image_info.height), .depth = 1 },
        };

        c.vkCmdCopyBufferToImage(command_buffer, staging_buffer, image_info.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        // Optimal shader layout translation
        const shader_read_barrier = c.VkImageMemoryBarrier{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .newLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image = image_info.image,
            .subresourceRange = image_info.subresource_range,
            .srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT,
            .dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT,
        };

        c.vkCmdPipelineBarrier(command_buffer, c.VK_PIPELINE_STAGE_TRANSFER_BIT, c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, &shader_read_barrier);

        _ = c.vkEndCommandBuffer(command_buffer);

        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer,
        };

        _ = c.vkQueueSubmit(self.present_queue, 1, &submit_info, null);
        _ = c.vkQueueWaitIdle(self.present_queue);

        c.vkFreeCommandBuffers(self.device, self.command_pool, 1, &command_buffer);

        c.vmaDestroyBuffer(self.vma_allocator, staging_buffer, staging_alloc);
}

/// Required fields are, image, viewType, format, and the subresource_range
pub fn create_image_view(device: c.VkDevice, image_info: *const ImageInfo) VkAbstractionError!void
{
    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image_info.*.image,
        .viewType = image_info.*.view_type,
        .format = image_info.*.format,
        .subresourceRange = image_info.*.subresource_range,
    };

    for (0..image_info.views.len) |i| {
        const success = c.vkCreateImageView(device, &view_info, null, &image_info.views[i]);
        if (success != c.VK_SUCCESS)
        {
            std.debug.print("Failed to create texture image view: {}\n", .{success}); return;
        }
    }
}

pub fn create_samplers(instance: *VulkanState, image_info: *ImageInfo, filter: c.VkFilter, repeat_mode: c.VkSamplerAddressMode, anisotropy: bool) VkAbstractionError!void
{
    const sampler_info = c.VkSamplerCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = filter,//c.VK_FILTER_LINEAR
        .minFilter = filter,
        .addressModeU = repeat_mode,//VK_SAMPLER_ADDRESS_MODE_REPEAT
        .addressModeV = repeat_mode,
        .addressModeW = repeat_mode,
        .anisotropyEnable = if (anisotropy) c.VK_TRUE else c.VK_FALSE,
        .maxAnisotropy = instance.physical_device_properties.limits.maxSamplerAnisotropy,
        .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = c.VK_FALSE,
        .compareEnable = c.VK_FALSE,
        .compareOp = c.VK_COMPARE_OP_ALWAYS,
        .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .mipLodBias = 0.0,
        .minLod = 0.0,
        .maxLod = 0.0,
    };
    
    for (0..image_info.samplers.len) |i| {
        const success = c.vkCreateSampler(instance.device, &sampler_info, null, &image_info.samplers[i]);
        if (success != c.VK_SUCCESS)
        {
            std.debug.print("Failed to create texture sampler: {}\n", .{success});
            return;
        }
    }
}

pub fn image_cleanup(self: *VulkanState, info: *ImageInfo) void
{
    for (0..info.views.len) |i|
    {
        c.vkDestroyImageView(self.device, info.views[i], null);
    }

    for (0..info.samplers.len) |i|
    {
        c.vkDestroySampler(self.device, info.samplers[i], null);
    }

    c.vmaDestroyImage(self.vma_allocator, info.image, info.alloc);
}

/// Creates a 4 byte aligned buffer of any given file, intended for reading SPIR-V binary files
fn read_sprv_file_aligned(allocator: *const std.mem.Allocator, file_name: []const u8) VkAbstractionError![]align(@sizeOf(u32)) u8 {
    const file_array = std.fs.cwd().readFileAllocOptions(allocator.*, file_name, 10000, null, @sizeOf(u32), null) catch |err| {
        std.debug.print("[Error] [IO] {}", .{err});
        return VkAbstractionError.ReadShaderFileFailed;
    };

    std.debug.print("[Info] \"{s}\" file length: {} aligned length: {}\n", .{ file_name, file_array.len, file_array.len / 4 });

    if (file_array.len % 4 != 0) {
        return VkAbstractionError.ShaderFileInvalidFileSize;
    }

    return file_array;
}

/// The formats returned in swapchain_support must be freed later
fn query_swapchain_support(self: *VulkanState) VkAbstractionError!swapchain_support {
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

    return result;
}

/// Initializes GLFW and checks for Vulkan support
pub fn glfw_initialization() VkAbstractionError!void {
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

pub fn glfw_error_callback(code: c_int, description: [*c]const u8) callconv(.C) void {
    std.debug.print("[Error] [GLFW] {} {s}\n", .{ code, description });
}

pub fn update_chunk_ssbo(self: *VulkanState, physics_state: *physics.PhysicsState, voxel_spaces: []chunk.VoxelSpace, ssbo_index: u32) VkAbstractionError!void {
    var data = std.ArrayList(ChunkRenderData).init(self.allocator.*);
    try data.ensureUnusedCapacity(voxel_spaces.len); // TODO maybe we do more later
    defer data.deinit();
    for (voxel_spaces) |vs| {
        for (0..vs.size[0] * vs.size[1] * vs.size[2]) |chunk_index| {
            const pos: @Vector(4, f32) = .{
                @as(f32, @floatCast(physics_state.particles.items[vs.physics_index].position[0])),
                @as(f32, @floatCast(physics_state.particles.items[vs.physics_index].position[1])),
                @as(f32, @floatCast(physics_state.particles.items[vs.physics_index].position[2])),
                0.0,
            };

            try data.append(.{
                .model = zm.translationV(pos),
                .size = vs.size,
                .pos = .{
                    @floatFromInt(chunk_index % vs.size[0] * 32),
                    @floatFromInt(chunk_index / vs.size[0] % vs.size[1] * 32),
                    @floatFromInt(chunk_index / vs.size[0] / vs.size[1] % vs.size[2] * 32),
                },
            });
        }
    }
    
    try self.copy_data_via_staging_buffer(&self.ssbo_buffers.items[ssbo_index], @intCast(data.items.len * @sizeOf(ChunkRenderData)), &data.items[0]);
}

pub fn render_thread(self: *VulkanState, game_state: *main.GameState, input_state: *main.InputState, physics_state: *physics.PhysicsState, done: *bool) !void {
    self.shader_modules = std.ArrayList(c.VkShaderModule).init(self.allocator.*);
    defer self.shader_modules.deinit();

    self.pipelines = try self.allocator.*.alloc(c.VkPipeline, 3);
    defer self.allocator.*.free(self.pipelines);

    self.vertex_buffers = std.ArrayList(c.VkBuffer).init(self.allocator.*);
    defer self.vertex_buffers.deinit();
    self.vertex_allocs = std.ArrayList(c.VmaAllocation).init(self.allocator.*);
    defer self.vertex_allocs.deinit();
    
    self.render_targets = std.ArrayList(RenderInfo).init(self.allocator.*);
    defer self.render_targets.deinit();

    self.ubo_buffers = std.ArrayList(c.VkBuffer).init(self.allocator.*);
    defer self.ubo_buffers.deinit();
    self.ubo_allocs = std.ArrayList(c.VmaAllocation).init(self.allocator.*);
    defer self.ubo_allocs.deinit();
    
    self.ssbo_buffers = std.ArrayList(c.VkBuffer).init(self.allocator.*);
    defer self.ssbo_buffers.deinit();
    self.ssbo_allocs = std.ArrayList(c.VmaAllocation).init(self.allocator.*);
    defer self.ssbo_allocs.deinit();

    self.command_buffers = try self.allocator.*.alloc(c.VkCommandBuffer, self.MAX_CONCURRENT_FRAMES);
    defer self.allocator.*.free(self.command_buffers);

    self.descriptor_sets = try self.allocator.*.alloc(c.VkDescriptorSet, self.MAX_CONCURRENT_FRAMES);
    defer self.allocator.*.free(self.descriptor_sets);

    self.image_available_semaphores = try self.allocator.*.alloc(c.VkSemaphore, self.MAX_CONCURRENT_FRAMES);
    defer self.allocator.*.free(self.image_available_semaphores);
    self.image_completion_semaphores = try self.allocator.*.alloc(c.VkSemaphore, self.MAX_CONCURRENT_FRAMES);
    defer self.allocator.*.free(self.image_completion_semaphores);
    self.in_flight_fences = try self.allocator.*.alloc(c.VkFence, self.MAX_CONCURRENT_FRAMES);
    defer self.allocator.*.free(self.in_flight_fences);

    const functions = c.VmaVulkanFunctions{
        .vkGetInstanceProcAddr = &c.vkGetInstanceProcAddr,
        .vkGetDeviceProcAddr = &c.vkGetDeviceProcAddr,
    };

    try self.create_surface();
    try self.pick_physical_device();
    c.vkGetPhysicalDeviceMemoryProperties(self.physical_device, &self.mem_properties);
    try self.create_present_queue(self.REQUIRE_FAMILIES);
    try self.create_swapchain();
    try self.create_swapchain_image_views();
    try self.create_descriptor_pool();

    try self.create_descriptor_set_layouts();

    const vma_allocator_create_info = c.VmaAllocatorCreateInfo{
        .flags = c.VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT,
        .vulkanApiVersion = c.VK_API_VERSION_1_2,
        .physicalDevice = self.physical_device,
        .device = self.device,
        .instance = self.vk_instance,
        .pVulkanFunctions = &functions,
    };
    
    const vma_allocator_success = c.vmaCreateAllocator(&vma_allocator_create_info, &self.vma_allocator);

    if (vma_allocator_success != c.VK_SUCCESS)
    {
        std.debug.print("Unable to create vma allocator {}\n", .{vma_allocator_success});
    }

    try self.create_depth_resources();

    self.push_constant_info = c.VkPushConstantRange{
        .stageFlags = c.VK_SHADER_STAGE_ALL,
        .offset = 0,
        // must be a multiple of 4
        .size = self.PUSH_CONSTANT_SIZE,
    };
    
    try self.create_pipeline_layout();
try self.create_render_pass();
    // cursor
    self.pipelines[0] = try self.create_generic_pipeline(cursor_vert_source, cursor_frag_source, false);
    // outline
    self.pipelines[1] = try self.create_outline_pipeline(outline_vert_source, outline_frag_source);
    // simple chunk
    self.pipelines[2] = try self.create_simple_chunk_pipeline(chunk_vert_source, chunk_frag_source, false);
    try self.create_framebuffers();
    try self.create_command_pool();
    try self.create_command_buffers();
    try self.create_sync_objects();

    // GLFW INIT
    c.glfwSetWindowSizeLimits(self.window, 240, 135, c.GLFW_DONT_CARE, c.GLFW_DONT_CARE);

    // cursor
    try self.render_targets.append(.{ .vertex_index = 0, .pipeline_index = 0});
    // outline
    try self.render_targets.append(.{ .vertex_index = 1, .pipeline_index = 1});
    
    try self.create_vertex_buffer(0, @sizeOf(Vertex), @intCast(cursor_vertices.len * @sizeOf(Vertex)), @ptrCast(@constCast(&cursor_vertices[0])));
    try self.create_vertex_buffer(1, @sizeOf(Vertex), @intCast(block_selection_cube.len * @sizeOf(Vertex)), @ptrCast(@constCast(&block_selection_cube[0])));

    //var chunk_render_data: std.ArrayList(ChunkRenderData) = std.ArrayList(ChunkRenderData).init(self.allocator.*);
    //defer chunk_render_data.deinit();

    var last_space_chunk_index: u32 = 0;
    // TODO add entries in a chunk data storage buffer for chunk pos etc.
    for (game_state.voxel_spaces.items, 0..game_state.voxel_spaces.items.len) |vs, space_index| {
        var mesh_data = std.ArrayList(ChunkVertex).init(self.allocator.*);
        defer mesh_data.deinit();

        for (0..vs.size[0] * vs.size[1] * vs.size[2]) |chunk_index| {
            // The goal is for this get chunk to be faster than reading the disk for an unmodified chunk
            const data = try chunk.get_chunk_data(game_state.seed, @intCast(space_index), .{0,0,0});
            const mesh_start: f64 = c.glfwGetTime();
            const new_vertices_count = try mesh_generation.cull_mesh(&data, @intCast(last_space_chunk_index + chunk_index), &mesh_data);
            std.debug.print("[Debug] time: {d:.4}ms \n", .{(c.glfwGetTime() - mesh_start) * 1000.0});
            _ = &new_vertices_count;
            std.debug.print("[Debug] vertice count: {}\n", .{new_vertices_count});
            
            //const pos: @Vector(4, f32) = .{
            //    @as(f32, @floatCast(physics_state.particles.items[vs.physics_index].position[0])),
            //    @as(f32, @floatCast(physics_state.particles.items[vs.physics_index].position[1])),
            //    @as(f32, @floatCast(physics_state.particles.items[vs.physics_index].position[2])),
            //    0.0,
            //};

            //try chunk_render_data.append(.{
            //    .model = zm.translationV(pos),//zm.translation(@as(f32, @floatFromInt(space_index * 2 + space_index)), 0.0, 0.0),
            //    .size = vs.size,
            //    .pos = .{
            //        @floatFromInt(chunk_index % vs.size[0] * 32),
            //        @floatFromInt(chunk_index / vs.size[0] % vs.size[1] * 32),
            //        @floatFromInt(chunk_index / vs.size[0] / vs.size[1] % vs.size[2] * 32),
            //    },
            //});
        }
        last_space_chunk_index += vs.size[0] * vs.size[1] * vs.size[2];

        const render_index: u32 = 2 + @as(u32, @intCast(space_index));
        game_state.voxel_spaces.items[space_index].render_index = render_index;
        try self.render_targets.append(.{ .vertex_index = render_index, .pipeline_index = 2, .vertex_render_offset = 0});
        try self.create_vertex_buffer(render_index, @sizeOf(ChunkVertex), @intCast(mesh_data.items.len * @sizeOf(ChunkVertex)), mesh_data.items.ptr);
    }


    // TODO initialize chunk data appropriately
    //try self.create_ssbo(@intCast(2 * @sizeOf(ChunkRenderData)), &chunk_render_data.items[0]);
    
    var ssbo: c.VkBuffer = undefined;
    var ssbo_alloc: c.VmaAllocation = undefined;
    
    var buffer_create_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = 2 * @sizeOf(ChunkRenderData),
        .usage = c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
    }; 
    
    const alloc_create_info = c.VmaAllocationCreateInfo{
        .usage = c.VMA_MEMORY_USAGE_AUTO,
        .flags = c.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
    };
    
    const buffer_success = c.vmaCreateBuffer(self.vma_allocator, &buffer_create_info, &alloc_create_info, &ssbo, &ssbo_alloc, null);
    
    if (buffer_success != c.VK_SUCCESS)
    {
        std.debug.print("success: {}\n", .{buffer_success});
        return VkAbstractionError.VertexBufferCreationFailure;
    }

    try self.ssbo_buffers.append(ssbo);
    try self.ssbo_allocs.append(ssbo_alloc);
    
    try update_chunk_ssbo(self, physics_state, game_state.voxel_spaces.items, 0);

    // RENDER INIT

    const BlockSelectorTransform = struct {
        model: zm.Mat = zm.identity(),
    };
    
    var selector_transform = BlockSelectorTransform{};

    const create_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = @sizeOf(BlockSelectorTransform),
        .usage = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
    };

    const ubo_alloc_create_info = c.VmaAllocationCreateInfo{
        .usage = c.VMA_MEMORY_USAGE_AUTO,
        .flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
    };

    for (0..self.vertex_buffers.items.len*self.MAX_CONCURRENT_FRAMES) |i|
    {
        _ = &i;
         
        var buffer: c.VkBuffer = undefined;
        var alloc: c.VmaAllocation = undefined;
        _ = c.vmaCreateBuffer(self.vma_allocator, &create_info, &ubo_alloc_create_info, &buffer, &alloc, null);
        
        _ = c.vmaCopyMemoryToAllocation(self.vma_allocator, &selector_transform, alloc, 0, @sizeOf(BlockSelectorTransform));
        try self.ubo_allocs.append(alloc);
        try self.ubo_buffers.append(buffer);
    }

    var image_info0 = ImageInfo{
        .depth = 1,
        .subresource_range = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .views = try self.allocator.*.alloc(c.VkImageView, self.MAX_CONCURRENT_FRAMES),
        .samplers = try self.allocator.*.alloc(c.VkSampler, self.MAX_CONCURRENT_FRAMES),
    };
    defer self.allocator.*.free(image_info0.views);
    defer self.allocator.*.free(image_info0.samplers);
   
    // TODO turn this into a one line conditional
    const image_data0 = c.stbi_load("fortnite.jpg", &image_info0.width, &image_info0.height, &image_info0.channels, c.STBI_rgb_alpha);
    if (image_data0 == null){
        std.debug.print("Unable to find image file \n", .{});
        return;
    }
    else
    {
        image_info0.data = image_data0;
    }

    try create_2d_texture(self, &image_info0);
    c.stbi_image_free(image_info0.data);

    try create_image_view(self.device, &image_info0);
    try create_samplers(self, &image_info0, c.VK_FILTER_LINEAR, c.VK_SAMPLER_ADDRESS_MODE_REPEAT, true);
    
    var image_info1 = ImageInfo{
        .depth = 1,
        .subresource_range = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .views = try self.allocator.*.alloc(c.VkImageView, self.MAX_CONCURRENT_FRAMES),
        .samplers = try self.allocator.*.alloc(c.VkSampler, self.MAX_CONCURRENT_FRAMES),
    };
    defer self.allocator.*.free(image_info1.views);
    defer self.allocator.*.free(image_info1.samplers);
   
    // TODO turn this into a one line conditional
    const image_data1 = c.stbi_load("blocks.png", &image_info1.width, &image_info1.height, &image_info1.channels, c.STBI_rgb_alpha);
    if (image_data1 == null){
        std.debug.print("Unable to find image file \n", .{});
        return;
    }
    else
    {
        image_info1.data = image_data1;
    }

    try create_2d_texture(self, &image_info1);
    c.stbi_image_free(image_info1.data);

    try create_image_view(self.device, &image_info1);
    try create_samplers(self, &image_info1, c.VK_FILTER_NEAREST, c.VK_SAMPLER_ADDRESS_MODE_REPEAT, false);

    // Descriptor Sets
    
    const layouts: [2]c.VkDescriptorSetLayout = .{self.descriptor_set_layout, self.descriptor_set_layout};
    const descriptor_alloc_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = self.descriptor_pool,
        .descriptorSetCount = self.MAX_CONCURRENT_FRAMES,
        .pSetLayouts = &layouts,
    };

    if (c.vkAllocateDescriptorSets(self.device, &descriptor_alloc_info, self.descriptor_sets.ptr) != c.VK_SUCCESS) {
        std.debug.print("Unable to allocate Descriptor Sets\n", .{});
    }
    
    for (0..self.MAX_CONCURRENT_FRAMES) |i| {
        const buffers: [2]c.VkDescriptorBufferInfo = .{
            c.VkDescriptorBufferInfo{
                .buffer = self.ubo_buffers.items[i],
                .offset = 0,
                .range = @sizeOf(BlockSelectorTransform),
            },
            c.VkDescriptorBufferInfo{
                .buffer = self.ssbo_buffers.items[0],
                .offset = 0,
                .range = 2 * @sizeOf(ChunkRenderData),
            },
        };
        
        const images: [2]c.VkDescriptorImageInfo = .{
            c.VkDescriptorImageInfo{
                .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                .imageView = image_info0.views[i],
                .sampler = image_info0.samplers[i],
            },
            c.VkDescriptorImageInfo{
                .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                .imageView = image_info1.views[i],
                .sampler = image_info1.samplers[i],
            }
        };

        const descriptor_writes: [4]c.VkWriteDescriptorSet = .{
            c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.descriptor_sets[i],
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = 1,
                .pBufferInfo = &buffers[0],
                .pImageInfo = null,
                .pTexelBufferView = null,
            },
            c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.descriptor_sets[i],
                .dstBinding = 1,
                .dstArrayElement = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .pBufferInfo = null,
                .pImageInfo = &images[0],
                .pTexelBufferView = null,
            },
            c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.descriptor_sets[i],
                .dstBinding = 2,
                .dstArrayElement = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .pBufferInfo = null,
                .pImageInfo = &images[1],
                .pTexelBufferView = null,
            },
            c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.descriptor_sets[i],
                .dstBinding = 3,
                .dstArrayElement = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount = 1,
                .pBufferInfo = &buffers[1],
                .pImageInfo = null,
                .pTexelBufferView = null,
            },
        };

        c.vkUpdateDescriptorSets(self.device, descriptor_writes.len, &descriptor_writes, 0, null);
    }

    self.push_constant_data = try self.allocator.*.alloc(u8, self.PUSH_CONSTANT_SIZE);
    defer self.allocator.*.free(self.push_constant_data);

    var frame_count: u64 = 0;
    var current_frame_index: u32 = 0;
    var previous_frame_time: f32 = 0.0;

    var window_height : i32 = 0;
    var window_width : i32 = 0;

    var frame_time_buffer_index: u32 = 0;
    var frame_time_cyclic_buffer: [256]f32 = undefined;
    // TODO replace this with splat?
    @memset(&frame_time_cyclic_buffer, 0.0);

    var render_state: []RenderInfo = try self.allocator.alloc(RenderInfo, self.render_targets.items.len);
    defer self.allocator.free(render_state);
    @memcpy(render_state, self.render_targets.items);

    while (c.glfwWindowShouldClose(self.window) == 0) {
        const current_time : f32 = @floatCast(c.glfwGetTime());
        const frame_delta: f32 = current_time - previous_frame_time;
        previous_frame_time = current_time;
        
        c.glfwPollEvents();

        c.glfwGetWindowSize(self.window, &window_width, &window_height);
        const aspect_ratio : f32 = @as(f32, @floatFromInt(window_width))/@as(f32, @floatFromInt(window_height));

        if (input_state.mouse_capture)
        {
            c.glfwSetInputMode(self.window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
        }
        else
        {
            c.glfwSetInputMode(self.window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
        }

        render_state = try self.allocator.realloc(render_state, self.render_targets.items.len);
        @memcpy(render_state, self.render_targets.items);

        // TODO move this out of the render loop somehow
        //  I think this is better than making the yaw a global state?
        if (@abs(input_state.mouse_dx) > 0.0 and input_state.mouse_capture) {
            game_state.player_state.yaw += @as(f32, @floatCast(input_state.mouse_dx * std.math.pi / 180.0 * input_state.MOUSE_SENSITIVITY));
            input_state.mouse_dx = 0.0;
        }
        
        if (@abs(input_state.mouse_dy) > 0.0 and input_state.mouse_capture) {
            game_state.player_state.pitch -= @as(f32, @floatCast(input_state.mouse_dy * std.math.pi / 180.0 * input_state.MOUSE_SENSITIVITY));
            input_state.mouse_dy = 0.0;
        }

        //// TODO make this based on a quaternion in player state
        const look = zm.normalize3(@Vector(4, f32){
            @as(f32, @floatCast(std.math.cos(game_state.player_state.yaw) * std.math.cos(game_state.player_state.pitch))),
            @as(f32, @floatCast(std.math.sin(game_state.player_state.pitch))),
            @as(f32, @floatCast(std.math.sin(game_state.player_state.yaw) * std.math.cos(game_state.player_state.pitch))),
            0.0,
        });
        //// Have this based on player gravity (an up in player state determined by logic/physics controllers)
        const up : zm.Vec = game_state.player_state.up;

        const player_pos: zm.Vec = .{
            @floatCast(physics_state.particles.items[game_state.player_state.physics_index].position[0]),
            @floatCast(physics_state.particles.items[game_state.player_state.physics_index].position[1]),
            @floatCast(physics_state.particles.items[game_state.player_state.physics_index].position[2]),
            0.0,
        };
        const view: zm.Mat = zm.lookToLh(player_pos, look, up);
        const projection: zm.Mat = zm.perspectiveFovLh(1.0, aspect_ratio, 0.1, 1000.0);
        const view_proj: zm.Mat = zm.mul(view, projection);
        
        
        @memcpy(self.push_constant_data[0..64], @as([]u8, @ptrCast(@constCast(&view_proj)))[0..64]);
        @memcpy(self.push_constant_data[@sizeOf(zm.Mat)..(@sizeOf(zm.Mat) + 4)], @as([*]u8, @ptrCast(@constCast(&aspect_ratio)))[0..4]);
        
        try update_chunk_ssbo(self, physics_state, game_state.voxel_spaces.items, 0);
        
        // DRAW
        try self.draw_frame(current_frame_index, &render_state);
        
        var average_frame_time: f32 = 0;
        for (frame_time_cyclic_buffer) |time|
        {
            average_frame_time += time;
        }
        average_frame_time /= 256;


        //std.debug.print("render state size: {} {any}\n", .{render_state.len, render_state});
        std.debug.print("\t\t\t| {s} pos:{d:2.1} {d:2.1} {d:2.1} y:{d:3.1} p:{d:3.1} {d:.3}ms\r", .{
            if (input_state.mouse_capture) "on " else "off",
            @as(f32, @floatCast(physics_state.particles.items[game_state.player_state.physics_index].position[0])), 
            @as(f32, @floatCast(physics_state.particles.items[game_state.player_state.physics_index].position[1])),
            @as(f32, @floatCast(physics_state.particles.items[game_state.player_state.physics_index].position[2])),
            game_state.player_state.yaw,
            game_state.player_state.pitch,
            average_frame_time * 1000.0,
        });

        frame_time_cyclic_buffer[frame_time_buffer_index] = frame_delta;
        if (frame_time_buffer_index < 255) {
            frame_time_buffer_index += 1;
        } else {
            frame_time_buffer_index = 0;
        }

        current_frame_index = (current_frame_index + 1) % self.MAX_CONCURRENT_FRAMES;
        frame_count += 1;
    }
    
    _ = c.vkDeviceWaitIdle(self.device);
    
    image_cleanup(self, &image_info0);
    image_cleanup(self, &image_info1);
    self.cleanup();
    
    done.* = true;
}
