//!Code pertaining to rendering and window creation
const std = @import("std");
const c = @import("clibs.zig");
const zm = @import("zmath");
const cm = @import("ceresmath.zig");
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

const COLOR: @Vector(3, f32) = .{32.0 / 256.0, 252.0 / 256.0, 164.0 / 256.0 };
const block_selection_cube: [17]Vertex = .{
    //front
    .{.pos = .{-0.001,-0.001,-0.001}, .color = COLOR },
    .{.pos = .{1.001,-0.001,-0.001}, .color = COLOR },
    .{.pos = .{1.001,1.001,-0.001}, .color = COLOR },
    .{.pos = .{-0.001,1.001,-0.001}, .color = COLOR },
    //left
    .{.pos = .{-0.001,-0.001,-0.001}, .color = COLOR },
    .{.pos = .{-0.001,-0.001,1.001}, .color = COLOR },
    .{.pos = .{-0.001,1.001,1.001}, .color = COLOR },
    .{.pos = .{-0.001,1.001,-0.001}, .color = COLOR },
    .{.pos = .{-0.001,-0.001,-0.001}, .color = COLOR },
    //right
    .{.pos = .{1.001,-0.001,-0.001}, .color = COLOR },
    .{.pos = .{1.001,-0.001,1.001}, .color = COLOR },
    .{.pos = .{1.001,1.001,1.001}, .color = COLOR },
    .{.pos = .{1.001,1.001,-0.001}, .color = COLOR },
    //back
    .{.pos = .{1.001,1.001,1.001}, .color = COLOR },
    .{.pos = .{-0.001,1.001,1.001}, .color = COLOR },
    .{.pos = .{-0.001,-0.001,1.001}, .color = COLOR },
    .{.pos = .{1.001,-0.001,1.001}, .color = COLOR },
};

const CURSOR_SCALE: f32 = 1.0 / 64.0;
const cursor_vertices: [6]Vertex = .{
    .{.pos = .{-CURSOR_SCALE,-CURSOR_SCALE,0.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{CURSOR_SCALE,CURSOR_SCALE,0.0}, .color = .{1.0,1.0,0.0}},
    .{.pos = .{-CURSOR_SCALE,CURSOR_SCALE,0.0}, .color = .{0.0,1.0,0.0}},
    .{.pos = .{-CURSOR_SCALE,-CURSOR_SCALE,0.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{CURSOR_SCALE,-CURSOR_SCALE,0.0}, .color = .{1.0,0.0,0.0}},
    .{.pos = .{CURSOR_SCALE,CURSOR_SCALE,0.0}, .color = .{1.0,1.0,0.0}},
};

// Attempt at descriptive Errors
pub const VkAbstractionError = error{
    Success,
    OutOfMemory,
    GLFWInitializationFailure,
    NullWindow,
    RequiredExtensionsFailure,
    VkInstanceCreationFailure,
    SurfaceCreationFailure,
    VulkanUnavailable,
    PhysicalDevicesCountFailure,
    EnumeratePhysicalDevicesFailure,
    InvalidDeviceCount,
    DeviceCreationFailure,
    RetrievePhysicalDeviceSurfaceCapabilitiesFailure,
    GetPhysicalDevicePresentModesFailure,
    RetrieveSurfaceFormatFailure,
    PhysicalDeviceInappropriateSwapchainSupport,
    CreateSwapchainFailure,
    GetSwapchainImagesFailure,
    CreateSwapchainImageViewsFailure,
    InappropriateGLFWFrameBufferSizeReturn,
    CreateShaderModuleFailure,
    ShaderFileInvalidFileSize,
    ReadShaderFileFailure,
    CreatePipelineLayoutFailure,
    CreatingRenderPassFailure,
    CreatingGraphicsPipelineFailure,
    FramebufferCreationFailure,
    CreateCommandPoolFailure,
    CommandBufferAllocationFailure,
    BeginRenderPassFailure,
    CompleteRenderPassFailure,
    InstanceLayerEnumerationFailure,
    CreateSyncObjectsFailure,
    EndRecordingFailure,
    AcquireNextSwapchainImageFailure,
    PresentationFailure,
    DescriptorSetCreationFailure,
    DeviceBufferAllocationFailure,
    DeviceBufferBindFailure,
    DescriptorPoolCreationFailure,
    SuitableDeviceMemoryTypeSelectionFailure,
    DepthFormatAvailablityFailure,
    DepthResourceCreationFailure,
    VertexBufferCreationFailure,
    UBOBufferCreationFailure,
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
    c.vulkan.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const swapchain_support = struct {
    capabilities: c.vulkan.VkSurfaceCapabilitiesKHR = undefined,
    formats: []c.vulkan.VkSurfaceFormatKHR = undefined,
    present_modes: []c.vulkan.VkPresentModeKHR = undefined,
};

/// Generic vertex format (Used by everything that isn't a chunk)
pub const Vertex = struct {
    pos: @Vector(3, f32),
    color: @Vector(3, f32),
};

/// Chunk specific vertex format
/// Given the uniqueness of each chunk's vertices it needs to have an index field for it's place in the UBO (or SBO)
pub const ChunkVertex = packed struct {
    index: u32,
    uv: @Vector(2, f32), // TODO Make the UV split into a texture index and the normal values (we can do basic lighting and have access to all textures using a texture atlas essentially with the same amount of data)
    pos: @Vector(3, f32),
};

/// Structure sent to the GPU for chunk unique data
const ChunkRenderData = struct {
    size: @Vector(3, u32),
    model: zm.Mat = zm.identity(),
};

/// All the state required to render a frame
/// This is to make sure all rendering state is seperate from the logic and physics state etc.vulkan.
pub const RenderFrame = struct {
    bodies: []physics.Body,
    particle_count: u32 = 0,
    voxel_spaces: []chunk.VoxelSpace,
    player_index: u32,
    /// ONLY EVER READ FROM THE CAMERA STATE NEVER WRITE ANY DATA EVER
    camera_state: *main.CameraState,
};

/// A "cyclic" buffer of RenderFrames for multithreading between the logic and render threads
pub const RenderFrameBuffer = struct {
    allocator: *std.mem.Allocator,
    size: u32,
    frame: []RenderFrame = undefined,
    mutex: []std.Thread.Mutex = undefined,

    pub fn init(
        self: *RenderFrameBuffer,
        camera_state: *main.CameraState,
        physics_state: *physics.PhysicsState,
        voxel_spaces: *[]chunk.VoxelSpace,
        player_index: u32
        ) !void {

        self.frame = try self.allocator.*.alloc(RenderFrame, self.size);
        self.mutex = try self.allocator.*.alloc(std.Thread.Mutex, self.size);

        for (0..self.size) |i| {
            self.mutex[i] = std.Thread.Mutex{};

            self.frame[i] = .{
                .voxel_spaces = try self.allocator.*.alloc(
                chunk.VoxelSpace,
                voxel_spaces.*.len
                ),
                .bodies = try self.allocator.*.alloc(
                physics.Body,
                physics_state.*.bodies.items.len
                ),
                .player_index = player_index,
                .camera_state = camera_state,
            };
            @memcpy(self.frame[i].voxel_spaces, voxel_spaces.*);
            @memcpy(self.frame[i].bodies, physics_state.*.bodies.items);
        }
    }

    /// This locks and unlocks the mutex associated with the buffer
    pub fn update(self: *RenderFrameBuffer,
        physics_state: *physics.PhysicsState,
        voxel_spaces: *[]chunk.VoxelSpace) !void {

        const frame_index: u32 = self.lock_render_frame();
        
        self.frame[frame_index].voxel_spaces = try self.allocator.realloc(
            self.frame[frame_index].voxel_spaces,
            voxel_spaces.*.len
            );
        self.frame[frame_index].bodies = try self.allocator.realloc(
            self.frame[frame_index].bodies,
            physics_state.*.bodies.items.len
            );
        @memcpy(self.frame[frame_index].voxel_spaces, voxel_spaces.*);
        @memcpy(self.frame[frame_index].bodies, physics_state.bodies.items);

        self.frame[frame_index].particle_count = physics_state.particle_count;

        self.mutex[frame_index].unlock();
    }

    // TODO add some way to prioritize less frequently used frames so we don't lock 
    // up when the logic thread hits its maximum delta time
    /// locks a mutex in the render frame buffer and returns
    pub fn lock_render_frame(self: *RenderFrameBuffer) u32 {
        var i: u32 = 0;
        var locked: bool = false;
        while (!locked) {
            //switch (calling_thread) {
            //    .logic => {
                    if (self.mutex[i].tryLock()) {
                        locked = true;
                    } else {
                        i = (i + 1) % self.size;
                    }
            //    },
            //    .render => {
            //        if (self.last_thread[i] != calling_thread) {
            //            if (self.mutex[i].tryLock()) {
            //                locked = true;
            //            } else {
            //                i = (i + 1) % self.size;
            //            }
            //        }
            //    },
            //}
        }

        //self.last_thread[i] = calling_thread;

        //std.debug.print("{}\n", .{i});
        return i;
    }

    pub fn deinit(self: *RenderFrameBuffer) void {

        for (0..self.size) |i| {
            self.allocator.*.free(self.frame[i].voxel_spaces);
            self.allocator.*.free(self.frame[i].bodies);
        }
        self.allocator.*.free(self.frame);
        self.allocator.*.free(self.mutex);
    } 
};


/// image_views size should be of size MAX_CONCURRENT_FRAMES
/// Current implementation also assumes 2D texture
/// Defaults to 2D image view type
/// Defaults to RGBA SRGB format
pub const ImageInfo = struct{
    data: *c.stb.stbi_uc = undefined,
    width: i32 = undefined,
    height: i32 = undefined,
    depth: i32 = undefined,
    channels: i32 = undefined,
    format: c.vulkan.VkFormat = c.vulkan.VK_FORMAT_R8G8B8A8_SRGB,
    view_type: c.vulkan.VkImageViewType = c.vulkan.VK_IMAGE_VIEW_TYPE_2D,
    image: c.vulkan.VkImage = undefined,
    alloc: c.vulkan.VmaAllocation = undefined,
    subresource_range: c.vulkan.VkImageSubresourceRange = undefined,
    views: []c.vulkan.VkImageView = undefined,
    samplers: []c.vulkan.VkSampler = undefined,
};

/// All the info required to render a vertex buffer
pub const RenderInfo = struct {
    vertex_index: u32,
    pipeline_index: u32,
    vertex_count: u32 = 0,
    vertex_buffer_offset: c.vulkan.VkDeviceSize = 0,
    vertex_render_offset: u32 = 0,
    instance_count: u32 = 1,
    rendering_enabled: bool = true,
};

/// The vulkan/render state
pub const VulkanState = struct {
    /// bitwise AND for more required queue bits (ie: compute)
    REQUIRE_FAMILIES: u32 = c.vulkan.VK_QUEUE_GRAPHICS_BIT,
    /// Corresponds to frame buffers, command buffers and more
    MAX_CONCURRENT_FRAMES: u32,

    ENGINE_NAME: *const [10:0]u8,

    /// CPU memory allocator
    allocator: *const std.mem.Allocator,

    /// GPU memory allocator
    vma_allocator: c.vulkan.VmaAllocator = undefined,

    vk_instance: c.vulkan.VkInstance = undefined,
    window: *c.vulkan.GLFWwindow = undefined,
    surface: c.vulkan.VkSurfaceKHR = undefined,

    physical_device: c.vulkan.VkPhysicalDevice = undefined,
    physical_device_properties: c.vulkan.VkPhysicalDeviceProperties = undefined,
    mem_properties: c.vulkan.VkPhysicalDeviceMemoryProperties = undefined,

    device: c.vulkan.VkDevice = undefined,
    queue_family_index: u32 = 0,
    present_queue: c.vulkan.VkQueue = undefined,

    swapchain: c.vulkan.VkSwapchainKHR = undefined,
    swapchain_format: c.vulkan.VkSurfaceFormatKHR = undefined,
    swapchain_images: []c.vulkan.VkImage = undefined,
    swapchain_image_views: []c.vulkan.VkImageView = undefined,
    swapchain_extent: c.vulkan.VkExtent2D = undefined,

    framebuffer_resized: bool = false,

    /// keeps track of shader modules
    shader_modules: std.ArrayList(c.vulkan.VkShaderModule) = undefined,

    descriptor_pool : c.vulkan.VkDescriptorPool = undefined,
    descriptor_sets : []c.vulkan.VkDescriptorSet = undefined,
    descriptor_set_layout : c.vulkan.VkDescriptorSetLayout = undefined,

    pipeline_layout: c.vulkan.VkPipelineLayout = undefined,
    renderpass: c.vulkan.VkRenderPass = undefined,
    pipelines: []c.vulkan.VkPipeline = undefined,
    frame_buffers: []c.vulkan.VkFramebuffer = undefined,
   
    /// Tells the renderer what to render according to a pipeline (shader + misc settings) and vertex data
    render_targets: std.ArrayList(RenderInfo) = undefined,
    // TODO refactor how render targets are determined (should be produced during runtime instead of being static)
    // scenes will likely be simple enough to do a runtime determination

    /// keeps track of GPU memory (Vertex buffers)
    vertex_buffers: std.ArrayList(c.vulkan.VkBuffer) = undefined,
    vertex_allocs: std.ArrayList(c.vulkan.VmaAllocation) = undefined,

    // keeps track of GPU memory (Uniform buffers)
    ubo_buffers: std.ArrayList(c.vulkan.VkBuffer) = undefined,
    ubo_allocs: std.ArrayList(c.vulkan.VmaAllocation) = undefined,

    images: []ImageInfo = undefined,

    command_pool: c.vulkan.VkCommandPool = undefined,
    command_buffers: []c.vulkan.VkCommandBuffer = undefined,

    // GPU timing structures
    image_available_semaphores: []c.vulkan.VkSemaphore = undefined,
    image_completion_semaphores: []c.vulkan.VkSemaphore = undefined,
    in_flight_fences: []c.vulkan.VkFence = undefined,

    // image data just for the depth buffer (absolutely necessary for 3D)
    depth_format: c.vulkan.VkFormat = undefined,
    depth_image: c.vulkan.VkImage = undefined,
    depth_image_alloc: c.vulkan.VmaAllocation = undefined,
    depth_image_view: c.vulkan.VkImageView = undefined,

    // Small, but immediate data, good for view-projection matrix
    PUSH_CONSTANT_SIZE: u32,
    push_constant_data: []u8 = undefined,
    push_constant_info: c.vulkan.VkPushConstantRange = undefined,

    chunk_render_style: mesh_generation.style,

    /// Creates our Vulkan instance and GLFW window
    pub fn window_setup(self: *VulkanState, application_name: []const u8, engine_name: []const u8) VkAbstractionError!void {
        c.vulkan.glfwWindowHint(c.vulkan.GLFW_CLIENT_API, c.vulkan.GLFW_NO_API);

        self.window = c.vulkan.glfwCreateWindow(800, 600, application_name.ptr, null, null) orelse return VkAbstractionError.NullWindow;

        const application_info = c.vulkan.VkApplicationInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = application_name.ptr,
            .pEngineName = engine_name.ptr,
            .engineVersion = c.vulkan.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = c.vulkan.VK_API_VERSION_1_2,
        };

        std.debug.print("[Info] Vulkan Application Info:\n", .{});
        std.debug.print("\tApplication name: {s}\n", .{application_info.pApplicationName});
        std.debug.print("\tEngine name: {s}\n", .{application_info.pEngineName});

        var required_extension_count: u32 = 0;
        const required_extensions = c.vulkan.glfwGetRequiredInstanceExtensions(&required_extension_count) orelse return VkAbstractionError.RequiredExtensionsFailure;

        var extensions_arraylist = try std.ArrayList([*:0]const u8).initCapacity(self.allocator.*, 16);
        defer extensions_arraylist.deinit(self.allocator.*);

        for (0..required_extension_count) |i| {
            try extensions_arraylist.append(self.allocator.*, required_extensions[i]);
        }

        for (instance_extensions) |extension| {
            try extensions_arraylist.append(self.allocator.*, extension);
        }

        std.debug.print("[Info] Vulkan Instance Extensions ({}):\n", .{extensions_arraylist.items.len});
        for (extensions_arraylist.items) |item| {
            std.debug.print("\t{s}\n", .{item});
        }

        var available_layers_count: u32 = 0;
        if (c.vulkan.vkEnumerateInstanceLayerProperties(&available_layers_count, null) != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.InstanceLayerEnumerationFailure;
        }

        const available_layers = try self.allocator.*.alloc(c.vulkan.VkLayerProperties, available_layers_count);
        defer self.allocator.*.free(available_layers);

        const enumeration_success = c.vulkan.vkEnumerateInstanceLayerProperties(&available_layers_count, available_layers.ptr);
        if (enumeration_success != c.vulkan.VK_SUCCESS) {
            std.debug.print("[Error] Enumeration failure: {}\n", .{enumeration_success});
            return VkAbstractionError.InstanceLayerEnumerationFailure;
        }

        std.debug.print("[Info] Available validation layers ({}):\n", .{available_layers.len});
        for (available_layers) |validation_layer| {
            std.debug.print("\t{s}\n", .{validation_layer.layerName});
        }

        std.debug.print("[Info] Vulkan Instance Validation layers ({}):\n", .{validation_layers.len});
        for (validation_layers) |validation_layer| {
            std.debug.print("\t{s}\n", .{validation_layer});
        }

        const create_info = c.vulkan.VkInstanceCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &application_info,
            .enabledLayerCount = if (std.debug.runtime_safety) @intCast(validation_layers.len) else 0,
            .ppEnabledLayerNames = if (std.debug.runtime_safety) &validation_layers else null,
            .enabledExtensionCount = @intCast(extensions_arraylist.items.len),
            .ppEnabledExtensionNames = extensions_arraylist.items.ptr,
        };

        const instance_result = c.vulkan.vkCreateInstance(&create_info, null, &self.vk_instance);

        if (instance_result != c.vulkan.VK_SUCCESS) {
            std.debug.print("[Error] Vk Instance Creation Failure: {}\n", .{instance_result});
            return VkAbstractionError.VkInstanceCreationFailure;
        }
    }

    pub fn create_surface(self: *VulkanState) VkAbstractionError!void {
        const success = c.vulkan.glfwCreateWindowSurface(self.vk_instance, self.window, null, &self.surface);

        if (success != c.vulkan.VK_SUCCESS) {
            std.debug.print("[Error] Surface Creation Failure: {}\n", .{success});
            return VkAbstractionError.SurfaceCreationFailure;
        }
    }

    /// Chooses a graphics device to use for rendering
    pub fn pick_physical_device(self: *VulkanState) VkAbstractionError!void {
        var device_count: u32 = 0;
        const physical_device_count_success = c.vulkan.vkEnumeratePhysicalDevices(self.vk_instance, &device_count, null);

        if (physical_device_count_success != c.vulkan.VK_SUCCESS) {
            std.debug.print("[Error] Unable to enumerate physical devices device_count: {} vk error code: {}\n", .{ device_count, physical_device_count_success });
            return VkAbstractionError.PhysicalDevicesCountFailure;
        }

        if (device_count <= 0) {
            return VkAbstractionError.InvalidDeviceCount;
        }

        const devices = try self.allocator.*.alloc(c.vulkan.VkPhysicalDevice, device_count);
        defer self.allocator.*.free(devices);
        const enumerate_physical_devices_success = c.vulkan.vkEnumeratePhysicalDevices(self.vk_instance, &device_count, devices.ptr);

        if (enumerate_physical_devices_success != c.vulkan.VK_SUCCESS) {
            std.debug.print("[Error] Unable to enumerate physical devices device_count: {} vk error code: {}\n", .{ device_count, enumerate_physical_devices_success });
            return VkAbstractionError.EnumeratePhysicalDevicesFailure;
        }

        self.physical_device = devices[0];

        var device_properties: c.vulkan.VkPhysicalDeviceProperties = undefined;
        c.vulkan.vkGetPhysicalDeviceProperties(self.physical_device, &device_properties);
        self.physical_device_properties = device_properties;

        std.debug.print("[Info] API version: {any}\n[Info] Driver version: {any}\n[Info] Device name: {s}\n", .{ device_properties.apiVersion, device_properties.driverVersion, device_properties.deviceName });

        // TODO Check for device extension compatibility
    }

    pub fn create_present_queue(self: *VulkanState, flags: u32) VkAbstractionError!void {
        const priority: f32 = 1.0;

        var queue_count: u32 = 0;
        _ = c.vulkan.vkGetPhysicalDeviceQueueFamilyProperties(self.*.physical_device, &queue_count, null);
        std.debug.print("[Info] Queue count: {}\n", .{queue_count});

        const properties = try self.allocator.*.alloc(c.vulkan.VkQueueFamilyProperties, queue_count);
        defer self.allocator.*.free(properties);
        _ = c.vulkan.vkGetPhysicalDeviceQueueFamilyProperties(self.*.physical_device, &queue_count, properties.ptr);

        var first_compatible: u32 = 0;
        // Top 10 moments where I love zig
        for (properties, 0..queue_count) |property, i| {
            if ((property.queueFlags & flags) == flags and first_compatible == 0) {
                first_compatible = @intCast(i);
            }
        }

        std.debug.print("[Info] First compatible: {}\n", .{first_compatible});

        self.queue_family_index = first_compatible;

        const queue_create_info = c.vulkan.VkDeviceQueueCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = first_compatible,
            .queueCount = 1,
            .pQueuePriorities = &priority,
        };

        // TODO add a way to specify device features
        const device_features = c.vulkan.VkPhysicalDeviceFeatures{
            .samplerAnisotropy = c.vulkan.VK_TRUE,
            .fillModeNonSolid = c.vulkan.VK_TRUE,
            .wideLines = c.vulkan.VK_TRUE,
        };

        const create_info = c.vulkan.VkDeviceCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pQueueCreateInfos = &queue_create_info,
            .queueCreateInfoCount = 1,
            .pEnabledFeatures = &device_features,
            .enabledExtensionCount = device_extensions.len,
            .ppEnabledExtensionNames = &device_extensions,
            .enabledLayerCount = validation_layers.len,
            .ppEnabledLayerNames = &validation_layers,
        };

        const device_creation_success = c.vulkan.vkCreateDevice(self.physical_device, &create_info, null, &self.device);
        if (device_creation_success != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.DeviceCreationFailure;
        }

        c.vulkan.vkGetDeviceQueue(self.device, first_compatible, 0, &self.present_queue);
    }

    pub fn create_swapchain(self: *VulkanState) VkAbstractionError!void {
        const support = try query_swapchain_support(self);
        defer self.allocator.*.free(support.formats);
        defer self.allocator.*.free(support.present_modes);

        //if (support.present_size > 0 and support.formats_size > 0) {
        var surface_format: c.vulkan.VkSurfaceFormatKHR = support.formats[0];
        std.debug.print("[Info] Swapchain minimum image count: {}\n", .{support.capabilities.minImageCount});
        var image_count: u32 = support.capabilities.minImageCount + 1;
        var format_index: u32 = 0;

        for (support.formats, 0..support.formats.len) |format, i| {
            if (format.format == c.vulkan.VK_FORMAT_B8G8R8A8_SRGB
                and format.colorSpace == c.vulkan.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                format_index = @intCast(i);
                surface_format = format;
                break;
            }
        }

        var present_mode: u32 = c.vulkan.VK_PRESENT_MODE_FIFO_KHR;
        for (support.present_modes) |mode| {
            if (mode == c.vulkan.VK_PRESENT_MODE_MAILBOX_KHR) {
                present_mode = c.vulkan.VK_PRESENT_MODE_MAILBOX_KHR;
            }
        }

        var extent: c.vulkan.VkExtent2D = undefined;
        var width: i32 = 0;
        var height: i32 = 0;
        std.debug.print("[Info] current extent: {} {}\n", .{ support.capabilities.currentExtent.width, support.capabilities.currentExtent.height });
        
        if (support.capabilities.currentExtent.width != std.math.maxInt(u32)) {
            extent = support.capabilities.currentExtent;
        } else {
            // This returns a signed integer
            c.vulkan.glfwGetFramebufferSize(self.window, &width, &height);

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

        const swapchain_create_info = c.vulkan.VkSwapchainCreateInfoKHR{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = self.surface,
            .minImageCount = image_count,
            .imageFormat = surface_format.format,
            .imageColorSpace = surface_format.colorSpace,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.vulkan.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = c.vulkan.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .preTransform = support.capabilities.currentTransform,
            .compositeAlpha = c.vulkan.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = present_mode,
            .clipped = c.vulkan.VK_TRUE,
            // This should be VK_NULL_HANDLE, but that is a opaque type and can't be casted properly,
            // After a quick look at the vulkan docs it appears to have cpp and msvc specific exceptions
            // however, our zig build should be compiling it in c and zig shouldn't be relying on
            // msvc either so replacing it with null outright should be ok...
            .oldSwapchain = null,
        };

        const swapchain_creation_success = c.vulkan.vkCreateSwapchainKHR(self.device, &swapchain_create_info, null, &self.swapchain);
        if (swapchain_creation_success != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.CreateSwapchainFailure;
        }

        const get_swapchain_images_success = c.vulkan.vkGetSwapchainImagesKHR(self.device, self.swapchain, &image_count, null);

        if (get_swapchain_images_success != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.GetSwapchainImagesFailure;
        }

        self.swapchain_images = try self.allocator.*.alloc(c.vulkan.VkImage, image_count);
        const get_swapchain_images_KHR = c.vulkan.vkGetSwapchainImagesKHR(self.device, self.swapchain, &image_count, self.swapchain_images.ptr);

        if (get_swapchain_images_KHR != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.GetSwapchainImagesFailure;
        }

        self.swapchain_format = surface_format;
        self.swapchain_extent = extent;

        std.debug.print("[Info] Swapchain final image count: {}\n", .{self.swapchain_images.len});
    }

    pub fn create_swapchain_image_views(self: *VulkanState) VkAbstractionError!void {
        self.swapchain_image_views = try self.allocator.*.alloc(c.vulkan.VkImageView, self.swapchain_images.len);
        for (0..self.swapchain_images.len) |i| {
            var create_info = c.vulkan.VkImageViewCreateInfo{
                .sType = c.vulkan.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = self.swapchain_images[i],
                .viewType = c.vulkan.VK_IMAGE_VIEW_TYPE_2D,
                .format = self.swapchain_format.format,
                .components = .{
                    .r = c.vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.vulkan.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = .{
                    .aspectMask = c.vulkan.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            const imageview_success = c.vulkan.vkCreateImageView(self.device, &create_info, null, self.swapchain_image_views.ptr + i);
            if (imageview_success != c.vulkan.VK_SUCCESS) {
                return VkAbstractionError.CreateSwapchainImageViewsFailure;
            }
        }
    }

    pub fn create_descriptor_pool(self : *VulkanState) VkAbstractionError!void {
        const ubo_pool_size = c.vulkan.VkDescriptorPoolSize{
            .type = c.vulkan.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 10,
        };
        
        const storage_pool_size = c.vulkan.VkDescriptorPoolSize{
            .type = c.vulkan.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 10,
        };
        
        const image_pool_size = c.vulkan.VkDescriptorPoolSize{
            .type = c.vulkan.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 10,
        };

        const pool_sizes : [3]c.vulkan.VkDescriptorPoolSize = 
            .{
                ubo_pool_size,
                storage_pool_size,
                image_pool_size,
            };

        const pool_info = c.vulkan.VkDescriptorPoolCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .poolSizeCount = pool_sizes.len,
            .pPoolSizes = &pool_sizes,
            .maxSets = self.MAX_CONCURRENT_FRAMES,
            .flags = c.vulkan.VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT,
        };
        
        const success = c.vulkan.vkCreateDescriptorPool(
            self.device,
            &pool_info,
            null,
            &self.descriptor_pool
            );
        if (success != c.vulkan.VK_SUCCESS)
        {
            std.debug.print("[Error] Unable to create Descriptor Pool: {}\n", .{success});
            return VkAbstractionError.DescriptorPoolCreationFailure;
        }
    }

    pub fn create_descriptor_set_layouts(self : *VulkanState) VkAbstractionError!void
    {
        // A description of the bindings and their contents
        // Essentially we need one of these per uniform buffer
        const layout_bindings: [4]c.vulkan.VkDescriptorSetLayoutBinding = .{
            c.vulkan.VkDescriptorSetLayoutBinding{
                .binding = 0,
                .descriptorCount = 1,
                .descriptorType = c.vulkan.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .stageFlags = c.vulkan.VK_SHADER_STAGE_ALL,//c.VK_SHADER_STAGE_VERTEX_BIT,
                .pImmutableSamplers = null,
            },
            c.vulkan.VkDescriptorSetLayoutBinding{
                .binding = 1,
                .descriptorCount = 1,
                .descriptorType = c.vulkan.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .stageFlags = c.vulkan.VK_SHADER_STAGE_ALL,//c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .pImmutableSamplers = null,
            },
            c.vulkan.VkDescriptorSetLayoutBinding{
                .binding = 2,
                .descriptorCount = 1,
                .descriptorType = c.vulkan.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .stageFlags = c.vulkan.VK_SHADER_STAGE_ALL,//c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .pImmutableSamplers = null,
            },
            c.vulkan.VkDescriptorSetLayoutBinding{
                .binding = 3,
                .descriptorCount = 1,
                .descriptorType = c.vulkan.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .stageFlags = c.vulkan.VK_SHADER_STAGE_ALL,
                .pImmutableSamplers = null,
            },
        };

        const layout_info = c.vulkan.VkDescriptorSetLayoutCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = @intCast(layout_bindings.len),
            .pBindings = &layout_bindings,
        };

        const descriptor_set_success = c.vulkan.vkCreateDescriptorSetLayout(
            self.device,
            &layout_info,
            null,
            &self.descriptor_set_layout
            );

        if (descriptor_set_success != c.vulkan.VK_SUCCESS) {
            
            std.debug.print(
                "[Error] Unable to create descriptor set: {}\n",
                .{descriptor_set_success}
                );
            
            return VkAbstractionError.DescriptorSetCreationFailure;
        }
    }

    /// Pipeline for arbitrary 3D geometry (vertices)
    pub fn create_pipeline(
        self: *VulkanState,
        vert_source: []align(4) u8,
        frag_source: []align(4) u8,
        wireframe: bool,
        binding_description: [*c]c.vulkan.VkVertexInputBindingDescription,
        binding_description_size: u32,
        attribute_description: [*c]c.vulkan.VkVertexInputAttributeDescription,
        attribute_description_size: u32,
        primitive: c.vulkan.VkPrimitiveTopology
        ) VkAbstractionError!c.vulkan.VkPipeline {

        const vert_index = self.shader_modules.items.len;
        try create_shader_module(self, vert_source);
        const frag_index = self.shader_modules.items.len;
        try create_shader_module(self, frag_source);

        const vertex_shader_stage = c.vulkan.VkPipelineShaderStageCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.vulkan.VK_SHADER_STAGE_VERTEX_BIT,
            .module = self.shader_modules.items[vert_index],
            .pName = "main",
        };

        const fragment_shader_stage = c.vulkan.VkPipelineShaderStageCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.vulkan.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = self.shader_modules.items[frag_index],
            .pName = "main",
        };

        const shader_stages: [2]c.vulkan.VkPipelineShaderStageCreateInfo = .{
            vertex_shader_stage,
            fragment_shader_stage,
        };

        const dynamic_state = [_]c.vulkan.VkDynamicState{
            c.vulkan.VK_DYNAMIC_STATE_VIEWPORT,
            c.vulkan.VK_DYNAMIC_STATE_SCISSOR,
        };

        const dynamic_state_create_info = c.vulkan.VkPipelineDynamicStateCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamic_state.len,
            .pDynamicStates = &dynamic_state,
        };


        const vertex_input_info = c.vulkan.VkPipelineVertexInputStateCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = binding_description_size,
            .pVertexBindingDescriptions = binding_description,
            .vertexAttributeDescriptionCount = attribute_description_size,
            .pVertexAttributeDescriptions = attribute_description,
        };

        const assembly_create_info = c.vulkan.VkPipelineInputAssemblyStateCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology = primitive,
            .primitiveRestartEnable = c.vulkan.VK_FALSE,
        };

        const viewport = c.vulkan.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(self.swapchain_extent.width),
            .height = @floatFromInt(self.swapchain_extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };

        const scissor = c.vulkan.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain_extent,
        };

        const viewport_create_info = c.vulkan.VkPipelineViewportStateCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .pViewports = &viewport,
            .scissorCount = 1,
            .pScissors = &scissor,
        };

        const rasterization_create_info = c.vulkan.VkPipelineRasterizationStateCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable = c.vulkan.VK_FALSE,
            .rasterizerDiscardEnable = c.vulkan.VK_FALSE,
            .polygonMode = if (wireframe) c.vulkan.VK_POLYGON_MODE_LINE else c.vulkan.VK_POLYGON_MODE_FILL,
            .lineWidth = 1.0,
            .cullMode = c.vulkan.VK_CULL_MODE_BACK_BIT,
            .frontFace = c.vulkan.VK_FRONT_FACE_CLOCKWISE,
            .depthBiasEnable = c.vulkan.VK_FALSE,
            .depthBiasConstantFactor = 0.0,
            .depthBiasClamp = 0.0,
            .depthBiasSlopeFactor = 0.0,
        };

        const multisampling_create_info = c.vulkan.VkPipelineMultisampleStateCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .sampleShadingEnable = c.vulkan.VK_FALSE,
            .rasterizationSamples = c.vulkan.VK_SAMPLE_COUNT_1_BIT,
            .minSampleShading = 1.0,
            .pSampleMask = null,
            .alphaToCoverageEnable = c.vulkan.VK_FALSE,
            .alphaToOneEnable = c.vulkan.VK_FALSE,
        };

        const color_blending_attachment_create_info = c.vulkan.VkPipelineColorBlendAttachmentState{
            .colorWriteMask = 
                c.vulkan.VK_COLOR_COMPONENT_R_BIT
                | c.vulkan.VK_COLOR_COMPONENT_G_BIT
                | c.vulkan.VK_COLOR_COMPONENT_B_BIT
                | c.vulkan.VK_COLOR_COMPONENT_A_BIT,
            .blendEnable = c.vulkan.VK_FALSE,
        };

        const color_blending_create_info = c.vulkan.VkPipelineColorBlendStateCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = c.vulkan.VK_FALSE,
            .logicOp = c.vulkan.VK_LOGIC_OP_COPY,
            .attachmentCount = 1,
            .pAttachments = &color_blending_attachment_create_info,
        };

        const depth_stencil_state_info = c.vulkan.VkPipelineDepthStencilStateCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable = c.vulkan.VK_TRUE,
            .depthWriteEnable = c.vulkan.VK_TRUE,
            .depthCompareOp = c.vulkan.VK_COMPARE_OP_LESS,
            .depthBoundsTestEnable = c.vulkan.VK_FALSE,
            .minDepthBounds = 0.0,
            .maxDepthBounds = 1.0,
            .stencilTestEnable = c.vulkan.VK_FALSE,
        };

        const pipeline_create_info = c.vulkan.VkGraphicsPipelineCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
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

        var pipeline: c.vulkan.VkPipeline = undefined;
        const pipeline_success = c.vulkan.vkCreateGraphicsPipelines(self.device, null, 1, &pipeline_create_info, null, &pipeline);
        if (pipeline_success != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.CreatingGraphicsPipelineFailure;
        }

        return pipeline;
    }

    /// Creates a shader module and appends the handler to the state's shader array list
    pub fn create_shader_module(self: *VulkanState, file_source : [] const align(4) u8) VkAbstractionError!void {
        var shader_module: c.vulkan.VkShaderModule = undefined;

        const create_info = c.vulkan.VkShaderModuleCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            // Size of the source in bytes not u32
            .codeSize = file_source.len,
            // This must be aligned to 4 bytes
            .pCode = @alignCast(@ptrCast(file_source.ptr)),
        };

        const create_shader_module_success = c.vulkan.vkCreateShaderModule(self.device, &create_info, null, &shader_module);
        if (create_shader_module_success != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.CreateShaderModuleFailure;
        }

        try self.shader_modules.append(self.allocator.*, shader_module);
    }

    pub fn create_framebuffers(self: *VulkanState) VkAbstractionError!void {
        self.frame_buffers = try self.allocator.*.alloc(c.vulkan.VkFramebuffer, self.swapchain_image_views.len);

        for (self.swapchain_image_views, 0..self.swapchain_image_views.len) |image_view, i| {

            const attachments: [2]c.vulkan.VkImageView = .{ image_view, self.depth_image_view };

            const framebuffer_create_info = c.vulkan.VkFramebufferCreateInfo{
                .sType = c.vulkan.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass = self.renderpass,
                .attachmentCount = attachments.len,
                .pAttachments = &attachments,
                .width = self.swapchain_extent.width,
                .height = self.swapchain_extent.height,
                .layers = 1,
            };

            const framebuffer_success = c.vulkan.vkCreateFramebuffer(self.device, &framebuffer_create_info, null, &self.frame_buffers[i]);
            if (framebuffer_success != c.vulkan.VK_SUCCESS) {
                return VkAbstractionError.FramebufferCreationFailure;
            }
        }
    }

    pub fn create_command_pool(self: *VulkanState) VkAbstractionError!void {
        const command_pool_info = c.vulkan.VkCommandPoolCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = c.vulkan.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = self.queue_family_index,
        };

        const command_pool_success = c.vulkan.vkCreateCommandPool(self.device, &command_pool_info, null, &self.command_pool);
        if (command_pool_success != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.CreateCommandPoolFailure;
        }
    }

    pub fn create_command_buffers(self: *VulkanState) VkAbstractionError!void {
        const allocation_info = c.vulkan.VkCommandBufferAllocateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = self.command_pool,
            .level = c.vulkan.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(self.command_buffers.len),
        };

        if (c.vulkan.vkAllocateCommandBuffers(self.device, &allocation_info, self.command_buffers.ptr) != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.CommandBufferAllocationFailure;
        }
    }

    /// Records the commands that produce a frame
    fn record_command_buffer(self: *VulkanState, command_buffer: c.vulkan.VkCommandBuffer, render_state: *[]RenderInfo, image_index: u32, frame_index: u32) VkAbstractionError!void {
        _ = &frame_index;

        const begin_info = c.vulkan.VkCommandBufferBeginInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = 0,
        };

        if (c.vulkan.vkBeginCommandBuffer(command_buffer, &begin_info) != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.BeginRenderPassFailure;
        }

        var clear_colors: [2]c.vulkan.VkClearValue = undefined;
        clear_colors[0].color.float32 = .{0.0, 0.003, 0.0005, 0.0};
        clear_colors[1].depthStencil = .{ .depth = 1.0, .stencil = 0 };

        const render_pass_info = c.vulkan.VkRenderPassBeginInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = self.renderpass,
            .framebuffer = self.frame_buffers[image_index],
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swapchain_extent,
            },
            .clearValueCount = clear_colors.len,
            .pClearValues = &clear_colors,
        };

        c.vulkan.vkCmdBeginRenderPass(command_buffer, &render_pass_info, c.vulkan.VK_SUBPASS_CONTENTS_INLINE);

        const viewport = c.vulkan.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(self.swapchain_extent.width),
            .height = @floatFromInt(self.swapchain_extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };

        c.vulkan.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

        const scissor = c.vulkan.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain_extent,
        };

        c.vulkan.vkCmdSetScissor(command_buffer, 0, 1, &scissor);
        
        c.vulkan.vkCmdPushConstants(command_buffer, self.pipeline_layout, c.vulkan.VK_SHADER_STAGE_ALL, 0, self.push_constant_info.size, &self.push_constant_data[0]);
        c.vulkan.vkCmdBindDescriptorSets(command_buffer, c.vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline_layout, 0, 1, &self.descriptor_sets[frame_index], 0, null);

        var previous_pipeline_index: u32 = std.math.maxInt(u32);
        for (render_state.*) |target| {
            const pipeline_index = target.pipeline_index;
            if (pipeline_index != previous_pipeline_index) {
                c.vulkan.vkCmdBindPipeline(
                    command_buffer,
                    c.vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS,
                    self.pipelines[pipeline_index]
                    );
                previous_pipeline_index = pipeline_index;
            }
            
            c.vulkan.vkCmdBindVertexBuffers(
                command_buffer,
                0,
                1,
                &self.vertex_buffers.items[target.vertex_index],
                &target.vertex_buffer_offset
                );
            
            c.vulkan.vkCmdDraw(command_buffer, target.vertex_count, target.instance_count, 0, 0);
        }

        c.vulkan.vkCmdEndRenderPass(command_buffer);
    }

    pub fn create_pipeline_layout(self: *VulkanState) VkAbstractionError!void {
        const pipeline_layout_create_info = c.vulkan.VkPipelineLayoutCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 1,
            .pSetLayouts = &self.descriptor_set_layout,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &self.push_constant_info,
        };

        const pipeline_layout_success = c.vulkan.vkCreatePipelineLayout(self.device, &pipeline_layout_create_info, null, &self.pipeline_layout);

        if (pipeline_layout_success != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.CreatePipelineLayoutFailure;
        }
    }

    pub fn create_render_pass(self: *VulkanState) VkAbstractionError!void {
        const color_attachment = c.vulkan.VkAttachmentDescription{
            .format = self.swapchain_format.format,
            .samples = c.vulkan.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = c.vulkan.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.vulkan.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = c.vulkan.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.vulkan.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = c.vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = c.vulkan.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        const color_attachment_ref = c.vulkan.VkAttachmentReference{
            .attachment = 0,
            .layout = c.vulkan.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };
        
        const depth_attachment = c.vulkan.VkAttachmentDescription{
            .format = self.depth_format,
            .samples = c.vulkan.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = c.vulkan.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.vulkan.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .stencilLoadOp = c.vulkan.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.vulkan.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = c.vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = c.vulkan.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };

        const depth_attachment_ref = c.vulkan.VkAttachmentReference{
            .attachment = 1,
            .layout = c.vulkan.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };
        
        const subpass = c.vulkan.VkSubpassDescription{
            .pipelineBindPoint = c.vulkan.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = 1,
            .pColorAttachments = &color_attachment_ref,
            .pDepthStencilAttachment = &depth_attachment_ref,
        };

        const attachments: [2]c.vulkan.VkAttachmentDescription = .{ color_attachment, depth_attachment };

        // Ensure the renderpass is waiting for our frames to complete
        const subpass_dependency = c.vulkan.VkSubpassDependency{
            .srcSubpass = c.vulkan.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = c.vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
                | c.vulkan.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .srcAccessMask = 0,
            .dstStageMask = c.vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
                | c.vulkan.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .dstAccessMask = c.vulkan.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
                | c.vulkan.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        };

        const renderpass_create_info = c.vulkan.VkRenderPassCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = attachments.len,
            .pAttachments = &attachments,
            .subpassCount = 1,
            .pSubpasses = &subpass,
            .dependencyCount = 1,
            .pDependencies = &subpass_dependency,
        };

        const render_pass_creation = c.vulkan.vkCreateRenderPass(self.device, &renderpass_create_info, null, &self.renderpass);
        if (render_pass_creation != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.CreatingRenderPassFailure;
        }
    }

    pub fn create_sync_objects(self: *VulkanState) VkAbstractionError!void {
        const image_available_semaphore_info = c.vulkan.VkSemaphoreCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        const image_completion_semaphore_info = c.vulkan.VkSemaphoreCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        const in_flight_fence_info = c.vulkan.VkFenceCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.vulkan.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        for (0..self.MAX_CONCURRENT_FRAMES) |i| {
            const success_a = c.vulkan.vkCreateSemaphore(self.device, &image_available_semaphore_info, null, &self.image_available_semaphores[i]);
            const success_b = c.vulkan.vkCreateSemaphore(self.device, &image_completion_semaphore_info, null, &self.image_completion_semaphores[i]);
            const success_c = c.vulkan.vkCreateFence(self.device, &in_flight_fence_info, null, &self.in_flight_fences[i]);

            if (success_a != c.vulkan.VK_SUCCESS or success_b != c.vulkan.VK_SUCCESS or success_c != c.vulkan.VK_SUCCESS) {
                return VkAbstractionError.CreateSyncObjectsFailure;
            }
        }
    }

    /// Determines which buffer to use (according to the number of concurrent frames and which was the previous one)
    /// It then submits the commands generated by record_command_buffer()
    pub fn draw_frame(self: *VulkanState, frame_index: u32, render_state: *[]RenderInfo) VkAbstractionError!void {
        const fence_wait = c.vulkan.vkWaitForFences(self.device, 1, &self.in_flight_fences[frame_index], c.vulkan.VK_TRUE, std.math.maxInt(u64));
        if (fence_wait != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }
        
        var image_index: u32 = 0;
        const acquire_next_image_success = c.vulkan.vkAcquireNextImageKHR(self.device, self.swapchain, std.math.maxInt(u64), self.image_available_semaphores[frame_index], null, &image_index);

        if (acquire_next_image_success == c.vulkan.VK_ERROR_OUT_OF_DATE_KHR or acquire_next_image_success == c.vulkan.VK_SUBOPTIMAL_KHR or self.framebuffer_resized) {
            try recreate_swapchain(self);
            self.framebuffer_resized = false;
            return;
        } else if (acquire_next_image_success != c.vulkan.VK_SUCCESS) {
            std.debug.print("[Error] Unable to acquire next swapchain image: {} \n", .{acquire_next_image_success});
            return VkAbstractionError.AcquireNextSwapchainImageFailure;
        }
        
        const reset_fence_success = c.vulkan.vkResetFences(self.device, 1, &self.in_flight_fences[frame_index]);
        if (reset_fence_success != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }

        if (c.vulkan.vkResetCommandBuffer(self.command_buffers[frame_index], 0) != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }

        try record_command_buffer(self, self.command_buffers[frame_index], render_state, image_index, frame_index);

        const end_recording_success = c.vulkan.vkEndCommandBuffer(self.command_buffers[frame_index]);
        if (end_recording_success != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.EndRecordingFailure;
        }

        const wait_stages = [_]c.vulkan.VkPipelineStageFlags{
            c.vulkan.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            //c.vulkan.VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT,
        };

        const submit_info = c.vulkan.VkSubmitInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.image_available_semaphores[frame_index],
            .pWaitDstStageMask = &wait_stages,
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &self.image_completion_semaphores[frame_index],
            .commandBufferCount = 1,
            .pCommandBuffers = &self.command_buffers[frame_index],
        };

        const queue_submit_success = c.vulkan.vkQueueSubmit(self.present_queue, 1, &submit_info, self.in_flight_fences[frame_index]);
        if (queue_submit_success != c.vulkan.VK_SUCCESS) {
            return VkAbstractionError.OutOfMemory;
        }

        const present_info = c.vulkan.VkPresentInfoKHR{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &self.image_completion_semaphores[frame_index],
            .swapchainCount = 1,
            .pSwapchains = &self.swapchain,
            .pImageIndices = &image_index,
        };

        const present_success = c.vulkan.vkQueuePresentKHR(self.present_queue, &present_info);
        if (present_success == c.vulkan.VK_SUBOPTIMAL_KHR or present_success == c.vulkan.VK_ERROR_OUT_OF_DATE_KHR or self.framebuffer_resized)
        {
            try recreate_swapchain(self);
            self.framebuffer_resized = false;
            return;
        } else if (present_success != c.vulkan.VK_SUCCESS) {
            std.debug.print("[Error] Presentation failure: {} \n", .{present_success});
            return VkAbstractionError.PresentationFailure;
        }
    }

    /// Image format does not matter
    pub fn create_depth_resources(self: *VulkanState) VkAbstractionError!void
    {
        const candidates: [3]c.vulkan.VkFormat = .{
            c.vulkan.VK_FORMAT_D32_SFLOAT,
            c.vulkan.VK_FORMAT_D32_SFLOAT_S8_UINT,
            c.vulkan.VK_FORMAT_D24_UNORM_S8_UINT
        };
        const format = try self.depth_texture_format(
            &candidates,
            c.vulkan.VK_IMAGE_TILING_OPTIMAL,
            c.vulkan.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT
            );
        self.depth_format = format;

        const image_create_info = c.vulkan.VkImageCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = c.vulkan.VK_IMAGE_TYPE_2D,
            .extent = .{ .width = self.swapchain_extent.width, .height = self.swapchain_extent.height, .depth = 1 },
            .mipLevels = 1,
            .arrayLayers = 1,
            .format = format,
            .tiling = c.vulkan.VK_IMAGE_TILING_OPTIMAL,
            .initialLayout = c.vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage = c.vulkan.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            .samples = c.vulkan.VK_SAMPLE_COUNT_1_BIT,
            .sharingMode = c.vulkan.VK_SHARING_MODE_EXCLUSIVE,
        };

        const alloc_info = c.vulkan.VmaAllocationCreateInfo{
            .usage = c.vulkan.VMA_MEMORY_USAGE_AUTO,
            .flags = c.vulkan.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
            .priority = 1.0,
        };

        const subresource_range = c.vulkan.VkImageSubresourceRange{
            .aspectMask = c.vulkan.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        };

        const depth_image_creation_success = c.vulkan.vmaCreateImage(self.vma_allocator, &image_create_info, &alloc_info, &self.depth_image, &self.depth_image_alloc, null);
        if (depth_image_creation_success != c.vulkan.VK_SUCCESS)
        {
            return VkAbstractionError.DepthResourceCreationFailure;
        }

        const view_info = c.vulkan.VkImageViewCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = self.depth_image,
            .viewType = c.vulkan.VK_IMAGE_VIEW_TYPE_2D,
            .format = format,
            .subresourceRange = subresource_range,
        };

        const success = c.vulkan.vkCreateImageView(self.device, &view_info, null, &self.depth_image_view);
        if (success != c.vulkan.VK_SUCCESS)
        {
            std.debug.print("Failure to create texture image view: {}\n", .{success}); return;
        }
    }

    /// Determines and returns the (best) supported depth resource format
    fn depth_texture_format(
        self: *VulkanState,
        candidates: []const c.vulkan.VkFormat,
        tiling: c.vulkan.VkImageTiling,
        features: c.vulkan.VkFormatFeatureFlags
        ) VkAbstractionError!c.vulkan.VkFormat {
        
        for (candidates) |format|
        {
            var properties : c.vulkan.VkFormatProperties = undefined;
            c.vulkan.vkGetPhysicalDeviceFormatProperties(self.physical_device, format, &properties);
    
            if (tiling == c.vulkan.VK_IMAGE_TILING_LINEAR and (properties.linearTilingFeatures & features) == features)
            {
                return format;
            }
            else if (tiling == c.vulkan.VK_IMAGE_TILING_OPTIMAL and (properties.optimalTilingFeatures & features) == features)
            {
                return format;
            }
        }
    
        return VkAbstractionError.DepthFormatAvailablityFailure;
    }

    fn cleanup_swapchain(self: *VulkanState) void {
        for (self.frame_buffers) |i| {
            c.vulkan.vkDestroyFramebuffer(self.device, i, null);
        }
        self.allocator.*.free(self.frame_buffers);

        for (self.swapchain_image_views) |image_view| {
            c.vulkan.vkDestroyImageView(self.device, image_view, null);
        }
        self.allocator.*.free(self.swapchain_image_views);
        c.vulkan.vkDestroySwapchainKHR(self.device, self.swapchain, null);
        self.allocator.*.free(self.swapchain_images);
    }

    /// Called whenever resizing a window
    pub fn recreate_swapchain(self: *VulkanState) VkAbstractionError!void {
        var width: i32 = 0;
        var height: i32 = 0;
        c.vulkan.glfwGetFramebufferSize(self.window, &width, &height);
        while (width == 0 or height == 0) {
            c.vulkan.glfwGetFramebufferSize(self.window, &width, &height);
            c.vulkan.glfwWaitEvents();
        }

        _ = c.vulkan.vkDeviceWaitIdle(self.device);

        cleanup_depth_resources(self);
        cleanup_swapchain(self);

        try create_swapchain(self);
        try create_swapchain_image_views(self);
        try create_depth_resources(self);
        try create_framebuffers(self);
    }

    pub fn cleanup_depth_resources(self: *VulkanState) void
    {
        c.vulkan.vkDestroyImageView(self.device, self.depth_image_view, null);
        c.vulkan.vmaDestroyImage(self.vma_allocator, self.depth_image, self.depth_image_alloc);
    }

    /// Copies any arbitrary CPU memory to the designated GPU buffer
    /// 
    /// ** WARNING **
    /// This function will overwrite data in adjacent memory
    /// if you specify a size larger than the allocated GPU buffer
    fn copy_data_via_staging_buffer(self: *VulkanState, final_buffer: *c.vulkan.VkBuffer, size: u32, data: *anyopaque) VkAbstractionError!void
    {
        var staging_buffer : c.vulkan.VkBuffer = undefined;

        const staging_buffer_info = c.vulkan.VkBufferCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = c.vulkan.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        };

        const staging_alloc_create_info = c.vulkan.VmaAllocationCreateInfo{
            .usage = c.vulkan.VMA_MEMORY_USAGE_AUTO,
            .flags = c.vulkan.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | c.vulkan.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        };

        var staging_alloc : c.vulkan.VmaAllocation = undefined;
        var staging_alloc_info : c.vulkan.VmaAllocationInfo = undefined;

        _ = c.vulkan.vmaCreateBuffer(self.vma_allocator, &staging_buffer_info, &staging_alloc_create_info, &staging_buffer, &staging_alloc, &staging_alloc_info);

        _ = c.vulkan.vmaCopyMemoryToAllocation(self.vma_allocator, data, staging_alloc, 0, size);
        
        const command_buffer_alloc_info = c.vulkan.VkCommandBufferAllocateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .level = c.vulkan.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandPool = self.command_pool,
            .commandBufferCount = 1,
        };
        var command_buffer : c.vulkan.VkCommandBuffer = undefined;
        const command_buffer_alloc_success = c.vulkan.vkAllocateCommandBuffers(self.device, &command_buffer_alloc_info, &command_buffer);
        if (command_buffer_alloc_success != c.vulkan.VK_SUCCESS)
        {
            std.debug.print("Unable to Allocate command buffer for image staging: {}\n", .{command_buffer_alloc_success});
            return;
        }

        // Copy and proper layout from staging buffer to gpu
        const begin_info = c.vulkan.VkCommandBufferBeginInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.vulkan.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };

        const begin_cmd_buffer = c.vulkan.vkBeginCommandBuffer(command_buffer, &begin_info);
        if (begin_cmd_buffer != c.vulkan.VK_SUCCESS)
        {
            return;
        }

        const transfer_barrier = c.vulkan.VkBufferMemoryBarrier{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
            .srcQueueFamilyIndex = c.vulkan.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.vulkan.VK_QUEUE_FAMILY_IGNORED,
            .buffer = final_buffer.*,
            .size = size,
            .srcAccessMask = 0,
            .dstAccessMask = c.vulkan.VK_ACCESS_TRANSFER_WRITE_BIT,
        };

        c.vulkan.vkCmdPipelineBarrier(
            command_buffer,
            c.vulkan.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            c.vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT,
            0,
            0,
            null,
            1,
            &transfer_barrier,
            0,
            null
            );
        
        const region = c.vulkan.VkBufferCopy{
            .srcOffset = 0,
            .dstOffset = 0,
            .size = size,
        };

        c.vulkan.vkCmdCopyBuffer(command_buffer, staging_buffer, final_buffer.*, 1, &region);
        // Optimal shader layout translation
        const buffer_read_barrier = c.vulkan.VkBufferMemoryBarrier{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
            .srcQueueFamilyIndex = c.vulkan.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.vulkan.VK_QUEUE_FAMILY_IGNORED,
            .srcAccessMask = c.vulkan.VK_ACCESS_TRANSFER_WRITE_BIT,
            .dstAccessMask = c.vulkan.VK_ACCESS_SHADER_READ_BIT,
            .buffer = final_buffer.*,
            .offset = 0,
            .size = size,
        };

        c.vulkan.vkCmdPipelineBarrier(
            command_buffer,
            c.vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT,
            c.vulkan.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0,
            0,
            null,
            1,
            &buffer_read_barrier,
            0,
            null
            );

        _ = c.vulkan.vkEndCommandBuffer(command_buffer);

        const submit_info = c.vulkan.VkSubmitInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer,
        };

        _ = c.vulkan.vkQueueSubmit(self.present_queue, 1, &submit_info, null);
        _ = c.vulkan.vkQueueWaitIdle(self.present_queue);

        c.vulkan.vkFreeCommandBuffers(self.device, self.command_pool, 1, &command_buffer);

        c.vulkan.vmaDestroyBuffer(self.vma_allocator, staging_buffer, staging_alloc);
    }
    
    pub fn create_vertex_buffer(self: *VulkanState, render_index: u32, stride_size: u32, size: u32, ptr: *anyopaque) VkAbstractionError!void
    {
        var vertex_buffer : c.vulkan.VkBuffer = undefined;
        var alloc: c.vulkan.VmaAllocation = undefined;
    
        var buffer_create_info = c.vulkan.VkBufferCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = c.vulkan.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | c.vulkan.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        }; 
    
        const alloc_create_info = c.vulkan.VmaAllocationCreateInfo{
            .usage = c.vulkan.VMA_MEMORY_USAGE_AUTO,
            .flags = c.vulkan.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
        };
    
        const buffer_success = c.vulkan.vmaCreateBuffer(self.vma_allocator, &buffer_create_info, &alloc_create_info, &vertex_buffer, &alloc, null);
        
        if (buffer_success != c.vulkan.VK_SUCCESS)
        {
            std.debug.print("success: {}\n", .{buffer_success});
            return VkAbstractionError.VertexBufferCreationFailure;
        }

        try self.copy_data_via_staging_buffer(&vertex_buffer, size, ptr);

        try self.vertex_buffers.append(self.allocator.*, vertex_buffer);
        try self.vertex_allocs.append(self.allocator.*, alloc);
        const vertex_count = size / stride_size;
        self.render_targets.items[render_index].vertex_count = vertex_count;
    }

    /// DEPRECATED
    pub fn replace_vertex_data(self: *VulkanState, render_index: u32, size: u32, ptr: *anyopaque) VkAbstractionError!void
    {
        // needs to occur asynchronously
        var vertex_buffer : c.vulkan.VkBuffer = undefined;
        var alloc: c.vulkan.VmaAllocation = undefined;
    
        var buffer_create_info = c.vulkan.VkBufferCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = c.vulkan.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | c.vulkan.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        }; 
    
        const alloc_create_info = c.vulkan.VmaAllocationCreateInfo{
            .usage = c.vulkan.VMA_MEMORY_USAGE_AUTO,
            .flags = c.vulkan.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
        };
    
        const buffer_success = c.vulkan.vmaCreateBuffer(self.vma_allocator, &buffer_create_info, &alloc_create_info, &vertex_buffer, &alloc, null);
        
        if (buffer_success != c.vulkan.VK_SUCCESS)
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
        
        c.vulkan.vmaDestroyBuffer(self.vma_allocator, old_buffer, old_alloc);
    }
    
    // TODO decide whether we want to make this host coherent based on the frequency
    // of chunk data updates
    // TODO make a way to modify the buffer at all, could replace it or change
    // data based on frequency and size...
    /// DEPRECATED
    pub fn create_ssbo(self: *VulkanState, size: u32, ptr: *anyopaque) VkAbstractionError!void
    {
        var ssbo: c.vulkan.VkBuffer = undefined;
        var alloc: c.vulkan.VmaAllocation = undefined;
    
        var buffer_create_info = c.vulkan.VkBufferCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = c.vulkan.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | c.vulkan.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        }; 
    
        const alloc_create_info = c.vulkan.VmaAllocationCreateInfo{
            .usage = c.vulkan.VMA_MEMORY_USAGE_AUTO,
            .flags = c.vulkan.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
        };
    
        const buffer_success = c.vulkan.vmaCreateBuffer(self.vma_allocator, &buffer_create_info, &alloc_create_info, &ssbo, &alloc, null);
        
        if (buffer_success != c.vulkan.VK_SUCCESS)
        {
            std.debug.print("success: {}\n", .{buffer_success});
            return VkAbstractionError.VertexBufferCreationFailure;
        }

        try self.copy_data_via_staging_buffer(&ssbo, size, ptr);

        try self.ssbo_buffers.append(self.allocator.*, ssbo);
        try self.ssbo_allocs.append(self.allocator.*, alloc);
    }

    pub fn create_voxel_space(self: *VulkanState, voxel_space: *chunk.VoxelSpace, space_index: u32) !void {
        var mesh_data = try std.ArrayList(ChunkVertex).initCapacity(self.allocator.*, 16);
        defer mesh_data.deinit();
    
        const vs = voxel_space.*;
        var last_space_chunk_index: u32 = 0;
        
        for (0..vs.size[0] * vs.size[1] * vs.size[2]) |chunk_index| {
            // The goal is for this get chunk to be faster than reading the disk for an unmodified chunk
            const data = try chunk.get_chunk_data(0, @intCast(space_index), .{0,0,0});
            const mesh_start: f64 = c.vulkan.glfwGetTime();
            const new_vertices_count = try mesh_generation.CullMesh(&data, @intCast(last_space_chunk_index + chunk_index), &mesh_data);
            std.debug.print("[Debug] time: {d:.4}ms \n", .{(c.vulkan.glfwGetTime() - mesh_start) * 1000.0});
            _ = &new_vertices_count;
        }
        last_space_chunk_index += vs.size[0] * vs.size[1] * vs.size[2];
       
        const render_index = 2 + space_index + last_space_chunk_index;
        try self.render_targets.append(
            self.allocator.*,
            .{
                .vertex_index = render_index,
                .pipeline_index = 2,
                .vertex_render_offset = 0,
            });
        try self.create_vertex_buffer(
            render_index,
            @sizeOf(ChunkVertex),
            @intCast(mesh_data.items.len * @sizeOf(ChunkVertex)),
            mesh_data.items.ptr);
    }

    /// Frees all Vulkan state
    /// All zig allocations should be deferred to after this function is called
    pub fn cleanup(self: *VulkanState) void {
        for (0..self.ubo_buffers.items.len) |i|
        {
            c.vulkan.vmaDestroyBuffer(self.vma_allocator, self.ubo_buffers.items[i], self.ubo_allocs.items[i]);
        }

        for (0..self.vertex_buffers.items.len) |i| {
            c.vulkan.vmaDestroyBuffer(self.vma_allocator, self.vertex_buffers.items[i], self.vertex_allocs.items[i]);
        }
        
        //for (0..self.ssbo_buffers.items.len) |i| {
        //    c.vulkan.vmaDestroyBuffer(self.vma_allocator, self.ssbo_buffers.items[i], self.ssbo_allocs.items[i]);
        //}

        for (0..self.MAX_CONCURRENT_FRAMES) |i| {
            c.vulkan.vkDestroySemaphore(self.device, self.image_available_semaphores[i], null);
            c.vulkan.vkDestroySemaphore(self.device, self.image_completion_semaphores[i], null);
            c.vulkan.vkDestroyFence(self.device, self.in_flight_fences[i], null);
        }

        c.vulkan.vkFreeCommandBuffers(self.device, self.command_pool, self.MAX_CONCURRENT_FRAMES, self.command_buffers.ptr);

        c.vulkan.vkDestroyCommandPool(self.device, self.command_pool, null);

        cleanup_depth_resources(self);
        cleanup_swapchain(self);
        
        for (0..self.shader_modules.items.len) |i| {
            c.vulkan.vkDestroyShaderModule(self.device, self.shader_modules.items[i], null);
        }

        for (0..self.pipelines.len) |i|
        {
            c.vulkan.vkDestroyPipeline(self.device, self.pipelines[i], null);
        }
        c.vulkan.vkDestroyRenderPass(self.device, self.renderpass, null);
      
        c.vulkan.vkDestroyDescriptorPool(self.device, self.descriptor_pool, null);
        
        c.vulkan.vkDestroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
        
        c.vulkan.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);

        c.vulkan.vkDestroySurfaceKHR(self.vk_instance, self.surface, null);
        c.vulkan.vmaDestroyAllocator(self.vma_allocator);
        c.vulkan.vkDestroyDevice(self.device, null);
        c.vulkan.vkDestroyInstance(self.vk_instance, null);
        c.vulkan.glfwDestroyWindow(self.window);
        c.vulkan.glfwTerminate();
    }
};

/// Image format must be assigned before this function
pub fn create_2d_texture(self: *VulkanState, image_info: *ImageInfo) VkAbstractionError!void
{
        const image_size : u64 = @intCast(image_info.width * image_info.height * 4);
        //Create staging buffer
        
        var staging_buffer : c.vulkan.VkBuffer = undefined;

        const staging_buffer_info = c.vulkan.VkBufferCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = image_size,
            .usage = c.vulkan.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        };

        const staging_alloc_create_info = c.vulkan.VmaAllocationCreateInfo{
            .usage = c.vulkan.VMA_MEMORY_USAGE_AUTO,
            .flags = c.vulkan.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | c.vulkan.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        };

        var staging_alloc : c.vulkan.VmaAllocation = undefined;
        var staging_alloc_info : c.vulkan.VmaAllocationInfo = undefined;

        _ = c.vulkan.vmaCreateBuffer(self.vma_allocator, &staging_buffer_info, &staging_alloc_create_info, &staging_buffer, &staging_alloc, &staging_alloc_info);

        _ = c.vulkan.vmaCopyMemoryToAllocation(self.vma_allocator, image_info.data, staging_alloc, 0, image_size);

        // Create image and transfer data to allocation

        const image_create_info = c.vulkan.VkImageCreateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = c.vulkan.VK_IMAGE_TYPE_2D,
            .extent = .{ .width = @intCast(image_info.width), .height = @intCast(image_info.height), .depth = 1},
            .mipLevels = 1,
            .arrayLayers = 1,
            .format = c.vulkan.VK_FORMAT_R8G8B8A8_SRGB,
            .tiling = c.vulkan.VK_IMAGE_TILING_OPTIMAL,
            .initialLayout = c.vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage = c.vulkan.VK_IMAGE_USAGE_SAMPLED_BIT | c.vulkan.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            .samples = c.vulkan.VK_SAMPLE_COUNT_1_BIT,
            .sharingMode = c.vulkan.VK_SHARING_MODE_EXCLUSIVE,
        };
        std.debug.print("width: {} height: {}\n", .{image_create_info.extent.width, image_create_info.extent.height});

        const alloc_info = c.vulkan.VmaAllocationCreateInfo{
            .usage = c.vulkan.VMA_MEMORY_USAGE_AUTO,
            .flags = c.vulkan.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,//c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,//, //| ,
            .priority = 1.0,
        };

        const image_creation = c.vulkan.vmaCreateImage(self.vma_allocator, &image_create_info, &alloc_info, &image_info.image, &image_info.alloc, null);
        if (image_creation != c.vulkan.VK_SUCCESS)
        {
            std.debug.print("Image creation failure: {}\n", .{image_creation});
            return;
        }
        
        const command_buffer_alloc_info = c.vulkan.VkCommandBufferAllocateInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .level = c.vulkan.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandPool = self.command_pool,
            .commandBufferCount = 1,
        };
        var command_buffer : c.vulkan.VkCommandBuffer = undefined;
        const command_buffer_alloc_success = c.vulkan.vkAllocateCommandBuffers(self.device, &command_buffer_alloc_info, &command_buffer);
        if (command_buffer_alloc_success != c.vulkan.VK_SUCCESS)
        {
            std.debug.print("Unable to Allocate command buffer for image staging: {}\n", .{command_buffer_alloc_success});
            return;
        }

        // Copy and proper layout from staging buffer to gpu
        const begin_info = c.vulkan.VkCommandBufferBeginInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.vulkan.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };

        const begin_cmd_buffer = c.vulkan.vkBeginCommandBuffer(command_buffer, &begin_info);
        if (begin_cmd_buffer != c.vulkan.VK_SUCCESS)
        {
            return;
        }
        
        // Translate to optimal tranfer layout

        const transfer_barrier = c.vulkan.VkImageMemoryBarrier{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = c.vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = c.vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = c.vulkan.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.vulkan.VK_QUEUE_FAMILY_IGNORED,
            .image = image_info.image,
            .subresourceRange = image_info.subresource_range,
            .srcAccessMask = 0,
            .dstAccessMask = c.vulkan.VK_ACCESS_TRANSFER_WRITE_BIT,
        };

        c.vulkan.vkCmdPipelineBarrier(
            command_buffer,
            c.vulkan.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            c.vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &transfer_barrier
            );
        
        // copy from staging buffer to image gpu destination
        const image_subresource = c.vulkan.VkImageSubresourceLayers{
            .aspectMask = c.vulkan.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        };
        
        const region = c.vulkan.VkBufferImageCopy{
            .bufferOffset = 0,
            .bufferRowLength = 0,
            .bufferImageHeight = 0,
            .imageSubresource = image_subresource,
            .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
            .imageExtent = .{ .width = @intCast(image_info.width), .height = @intCast(image_info.height), .depth = 1 },
        };

        c.vulkan.vkCmdCopyBufferToImage(
            command_buffer,
            staging_buffer,
            image_info.image,
            c.vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &region
            );
        // Optimal shader layout translation
        const shader_read_barrier = c.vulkan.VkImageMemoryBarrier{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = c.vulkan.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .newLayout = c.vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .srcQueueFamilyIndex = c.vulkan.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.vulkan.VK_QUEUE_FAMILY_IGNORED,
            .image = image_info.image,
            .subresourceRange = image_info.subresource_range,
            .srcAccessMask = c.vulkan.VK_ACCESS_TRANSFER_WRITE_BIT,
            .dstAccessMask = c.vulkan.VK_ACCESS_SHADER_READ_BIT,
        };

        c.vulkan.vkCmdPipelineBarrier(
            command_buffer,
            c.vulkan.VK_PIPELINE_STAGE_TRANSFER_BIT,
            c.vulkan.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &shader_read_barrier
            );

_ = c.vulkan.vkEndCommandBuffer(command_buffer);

        const submit_info = c.vulkan.VkSubmitInfo{
            .sType = c.vulkan.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer,
        };

        _ = c.vulkan.vkQueueSubmit(self.present_queue, 1, &submit_info, null);
        _ = c.vulkan.vkQueueWaitIdle(self.present_queue);

        c.vulkan.vkFreeCommandBuffers(self.device, self.command_pool, 1, &command_buffer);

        c.vulkan.vmaDestroyBuffer(self.vma_allocator, staging_buffer, staging_alloc);
}

/// Required fields are, image, viewType, format, and the subresource_range
pub fn create_image_view(device: c.vulkan.VkDevice, image_info: *const ImageInfo) VkAbstractionError!void
{
    const view_info = c.vulkan.VkImageViewCreateInfo{
        .sType = c.vulkan.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image_info.*.image,
        .viewType = image_info.*.view_type,
        .format = image_info.*.format,
        .subresourceRange = image_info.*.subresource_range,
    };

    for (0..image_info.views.len) |i| {
        const success = c.vulkan.vkCreateImageView(device, &view_info, null, &image_info.views[i]);
        if (success != c.vulkan.VK_SUCCESS)
        {
            std.debug.print("Failure to create texture image view: {}\n", .{success}); return;
        }
    }
}

pub fn create_samplers(
    instance: *VulkanState,
    image_info: *ImageInfo,
    filter: c.vulkan.VkFilter,
    repeat_mode: c.vulkan.VkSamplerAddressMode,
    anisotropy: bool
    ) VkAbstractionError!void {

    const sampler_info = c.vulkan.VkSamplerCreateInfo{
        .sType = c.vulkan.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = filter,//c.vulkan.VK_FILTER_LINEAR
        .minFilter = filter,
        .addressModeU = repeat_mode,//VK_SAMPLER_ADDRESS_MODE_REPEAT
        .addressModeV = repeat_mode,
        .addressModeW = repeat_mode,
        .anisotropyEnable = if (anisotropy) c.vulkan.VK_TRUE else c.vulkan.VK_FALSE,
        .maxAnisotropy = instance.physical_device_properties.limits.maxSamplerAnisotropy,
        .borderColor = c.vulkan.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = c.vulkan.VK_FALSE,
        .compareEnable = c.vulkan.VK_FALSE,
        .compareOp = c.vulkan.VK_COMPARE_OP_ALWAYS,
        .mipmapMode = c.vulkan.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .mipLodBias = 0.0,
        .minLod = 0.0,
        .maxLod = 0.0,
    };
    
    for (0..image_info.samplers.len) |i| {
        const success = c.vulkan.vkCreateSampler(instance.device, &sampler_info, null, &image_info.samplers[i]);
        if (success != c.vulkan.VK_SUCCESS)
        {
            std.debug.print("Failure to create texture sampler: {}\n", .{success});
            return;
        }
    }
}

pub fn image_cleanup(self: *VulkanState, info: *ImageInfo) void
{
    for (0..info.views.len) |i|
    {
        c.vulkan.vkDestroyImageView(self.device, info.views[i], null);
    }

    for (0..info.samplers.len) |i|
    {
        c.vulkan.vkDestroySampler(self.device, info.samplers[i], null);
    }

    c.vulkan.vmaDestroyImage(self.vma_allocator, info.image, info.alloc);
}

/// Creates a 4 byte aligned buffer of any given file, intended for reading SPIR-V binary files
fn read_sprv_file_aligned(allocator: *const std.mem.Allocator, file_name: []const u8) VkAbstractionError![]align(@sizeOf(u32)) u8 {
    const file_array = std.fs.cwd().readFileAllocOptions(allocator.*, file_name, 10000, null, @sizeOf(u32), null) catch |err| {
        std.debug.print("[Error] [IO] {}", .{err});
        return VkAbstractionError.ReadShaderFileFailure;
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

    const surface_capabilities_success = c.vulkan.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(self.physical_device, self.surface, &result.capabilities);
    if (surface_capabilities_success != c.vulkan.VK_SUCCESS) {
        return VkAbstractionError.RetrievePhysicalDeviceSurfaceCapabilitiesFailure;
    }

    var format_count: u32 = 0;
    const get_physical_device_surface_formats = c.vulkan.vkGetPhysicalDeviceSurfaceFormatsKHR(self.physical_device, self.surface, &format_count, null);
    std.debug.print("[Info] Surface format count: {}\n", .{format_count});

    if (get_physical_device_surface_formats != c.vulkan.VK_SUCCESS or format_count < 0) {
        return VkAbstractionError.RetrieveSurfaceFormatFailure;
    }

    result.formats = try self.allocator.*.alloc(c.vulkan.VkSurfaceFormatKHR, format_count);

    const retrieve_formats_success = c.vulkan.vkGetPhysicalDeviceSurfaceFormatsKHR(self.physical_device, self.surface, &format_count, result.formats.ptr);
    if (retrieve_formats_success != c.vulkan.VK_SUCCESS) {
        return VkAbstractionError.RetrieveSurfaceFormatFailure;
    }

    var present_modes: u32 = 0;
    var get_physical_device_present_modes = c.vulkan.vkGetPhysicalDeviceSurfacePresentModesKHR(self.physical_device, self.surface, &present_modes, null);
    if (get_physical_device_present_modes != c.vulkan.VK_SUCCESS or present_modes < 0) {
        return VkAbstractionError.GetPhysicalDevicePresentModesFailure;
    }

    std.debug.print("[Info] Presentation Count: {}\n", .{present_modes});

    result.present_modes = try self.allocator.*.alloc(c.vulkan.VkPresentModeKHR, present_modes);

    get_physical_device_present_modes = c.vulkan.vkGetPhysicalDeviceSurfacePresentModesKHR(self.physical_device, self.surface, &present_modes, result.present_modes.ptr);
    if (get_physical_device_present_modes != c.vulkan.VK_SUCCESS) {
        return VkAbstractionError.GetPhysicalDevicePresentModesFailure;
    }

    return result;
}

/// Initializes GLFW and checks for Vulkan support
pub fn glfw_initialization() VkAbstractionError!void {
    if (c.vulkan.glfwInit() != c.vulkan.GLFW_TRUE) {
        return VkAbstractionError.GLFWInitializationFailure;
    }

    const vulkan_support = c.vulkan.glfwVulkanSupported();
    if (vulkan_support != c.vulkan.GLFW_TRUE) {
        std.debug.print("[Error] GLFW could not find Vulkan support.\n", .{});
        return VkAbstractionError.VulkanUnavailable;
    }

    _ = c.vulkan.glfwSetErrorCallback(glfw_error_callback);
}

pub export fn glfw_error_callback(code: c_int, description: [*c]const u8) void {
    std.debug.print("[Error] [GLFW] {} {s}\n", .{ code, description });
}

/// Generates the unique data sent to the GPU for chunks
pub fn update_chunk_ubo(self: *VulkanState, bodies: []physics.Body, ubo_index: u32) VkAbstractionError!void {
    var data = try std.ArrayList(ChunkRenderData).initCapacity(self.allocator.*, 16);
    defer data.deinit(self.allocator.*);

    // Iterating through every single physics body reeks a little to me,
    // but tbh, not sure I can do much about that atm
    for (bodies) |body| {
        if (body.body_type == .voxel_space) {
            const vs = body.voxel_space.*;
            for (0..vs.size[0] * vs.size[1] * vs.size[2]) |chunk_index| {
                const physics_pos = .{
                    @as(f32, @floatCast(bodies[vs.physics_index].position[0])),
                    @as(f32, @floatCast(bodies[vs.physics_index].position[1])),
                    @as(f32, @floatCast(bodies[vs.physics_index].position[2])),
                };
                const pos: @Vector(4, f32) = .{
                    physics_pos[0] +
                        @as(f32, @floatFromInt(chunk_index % vs.size[0] * 32)),
                    physics_pos[1] +
                        @as(f32, @floatFromInt(chunk_index / vs.size[0] % vs.size[1] * 32)),
                    physics_pos[2] +
                        @as(f32, @floatFromInt(chunk_index / vs.size[0] / vs.size[1] % vs.size[2] * 32)),
                    0.0,
                };

                const model = zm.mul(zm.quatToMat(bodies[vs.physics_index].orientation), zm.translationV(pos));

                try data.append(
                    self.allocator.*,
                    .{
                    .model = model,
                    .size = vs.size,
                });
            }
        }
    }
    
    try self.copy_data_via_staging_buffer(&self.ubo_buffers.items[ubo_index], @intCast(data.items.len * @sizeOf(ChunkRenderData)), &data.items[0]);
}

/// Generates the unique data sent to the GPU for particles
///
/// returns the number of particles sent to the GPU (used for instance rendering)
pub fn update_particle_ubo(self: *VulkanState, bodies: []physics.Body, player_index: u32, ubo_index: u32) VkAbstractionError!void {
    var data = try std.ArrayList(zm.Mat).initCapacity(self.allocator.*, 64);
    defer data.deinit(self.allocator.*);

    for (bodies) |body| {
        if (body.body_type == .particle) {
            try data.append(
                self.allocator.*,
                body.render_transform(bodies[player_index].position)
                );
        }
    }

    if (data.items.len > 0) {
        try self.copy_data_via_staging_buffer(&self.ubo_buffers.items[ubo_index], @intCast(data.items.len * @sizeOf(zm.Mat)), &data.items[0]);
    }
}


//THREAD
/// Initializes all required boilerplate for the render state
pub fn render_init(self: *VulkanState) !void {
    self.shader_modules = try std.ArrayList(c.vulkan.VkShaderModule).initCapacity(self.allocator.*, 8);
    defer self.shader_modules.deinit(self.allocator.*);

    self.pipelines = try self.allocator.*.alloc(c.vulkan.VkPipeline, 3);
    defer self.allocator.*.free(self.pipelines);

    self.vertex_buffers = try std.ArrayList(c.vulkan.VkBuffer).initCapacity(self.allocator.*, 8);
    defer self.vertex_buffers.deinit(self.allocator.*);
    self.vertex_allocs = try std.ArrayList(c.vulkan.VmaAllocation).initCapacity(self.allocator.*, 8);
    defer self.vertex_allocs.deinit(self.allocator.*);
   
    self.ubo_buffers = try std.ArrayList(c.vulkan.VkBuffer).initCapacity(self.allocator.*, 8);
    defer self.ubo_buffers.deinit(self.allocator.*);
    self.ubo_allocs = try std.ArrayList(c.vulkan.VmaAllocation).initCapacity(self.allocator.*, 8);
    defer self.ubo_allocs.deinit(self.allocator.*);

    self.render_targets = try std.ArrayList(RenderInfo).initCapacity(self.allocator.*, 8);
    defer self.render_targets.deinit(self.allocator.*);

    self.command_buffers = try self.allocator.*.alloc(c.vulkan.VkCommandBuffer, self.MAX_CONCURRENT_FRAMES);
    defer self.allocator.*.free(self.command_buffers);

    self.descriptor_sets = try self.allocator.*.alloc(c.vulkan.VkDescriptorSet, self.MAX_CONCURRENT_FRAMES);
    defer self.allocator.*.free(self.descriptor_sets);

    self.image_available_semaphores = try self.allocator.*.alloc(c.vulkan.VkSemaphore, self.MAX_CONCURRENT_FRAMES);
    defer self.allocator.*.free(self.image_available_semaphores);
    self.image_completion_semaphores = try self.allocator.*.alloc(c.vulkan.VkSemaphore, self.MAX_CONCURRENT_FRAMES);
    defer self.allocator.*.free(self.image_completion_semaphores);
    self.in_flight_fences = try self.allocator.*.alloc(c.vulkan.VkFence, self.MAX_CONCURRENT_FRAMES);
    defer self.allocator.*.free(self.in_flight_fences);

    const functions = c.vulkan.VmaVulkanFunctions{
        .vkGetInstanceProcAddr = &c.vulkan.vkGetInstanceProcAddr,
        .vkGetDeviceProcAddr = &c.vulkan.vkGetDeviceProcAddr,
    };

    try self.create_surface();
    try self.pick_physical_device();
    c.vulkan.vkGetPhysicalDeviceMemoryProperties(self.physical_device, &self.mem_properties);
    try self.create_present_queue(self.REQUIRE_FAMILIES);
    try self.create_swapchain();
    try self.create_swapchain_image_views();
    try self.create_descriptor_pool();

    try self.create_descriptor_set_layouts();

    const vma_allocator_create_info = c.vulkan.VmaAllocatorCreateInfo{
        .flags = c.vulkan.VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT,
        .vulkanApiVersion = c.vulkan.VK_API_VERSION_1_2,
        .physicalDevice = self.physical_device,
        .device = self.device,
        .instance = self.vk_instance,
        .pVulkanFunctions = &functions,
    };
    
    const vma_allocator_success = c.vulkan.vmaCreateAllocator(&vma_allocator_create_info, &self.vma_allocator);

    if (vma_allocator_success != c.vulkan.VK_SUCCESS)
    {
        std.debug.print("Unable to create vma allocator {}\n", .{vma_allocator_success});
    }

    try self.create_depth_resources();

    self.push_constant_info = c.vulkan.VkPushConstantRange{
        .stageFlags = c.vulkan.VK_SHADER_STAGE_ALL,
        .offset = 0,
        // must be a multiple of 4
        .size = self.PUSH_CONSTANT_SIZE,
    };
    
    try self.create_pipeline_layout();
    try self.create_render_pass();
    
    var generic_binding_description: [1]c.vulkan.VkVertexInputBindingDescription = .{ 
        c.vulkan.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = c.vulkan.VK_VERTEX_INPUT_RATE_VERTEX,
        }
    };
    
    var chunk_binding_description: [1]c.vulkan.VkVertexInputBindingDescription = .{ 
        c.vulkan.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(ChunkVertex),
            .inputRate = c.vulkan.VK_VERTEX_INPUT_RATE_VERTEX,
        }
    };
    
    var generic_attribute_description: [2]c.vulkan.VkVertexInputAttributeDescription =    .{
        .{
            .binding = 0,
            .location = 0,
            .format = c.vulkan.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = 0
        },
        .{
            .binding = 0,
            .location = 1,
            .format = c.vulkan.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = @sizeOf(@Vector(3, f32))
        },
    };
    
    var chunk_attribute_description: [3]c.vulkan.VkVertexInputAttributeDescription =    .{
        .{
            .binding = 0,
            .location = 0,
            .format = c.vulkan.VK_FORMAT_R32_UINT,
            .offset = 0
        },
        .{
            .binding = 0,
            .location = 1,
            .format = c.vulkan.VK_FORMAT_R32G32_SFLOAT,
            .offset = @sizeOf(u32)
        },
        .{
            .binding = 0,
            .location = 2,
            .format = c.vulkan.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = @sizeOf(u32) + @sizeOf(@Vector(2, f32))
        },
    };

    // cursor
    self.pipelines[0] = try self.create_pipeline(
        cursor_vert_source,
        cursor_frag_source,
        false,
        &generic_binding_description,
        @intCast(generic_binding_description.len),
        &generic_attribute_description,
        @intCast(generic_attribute_description.len),
        c.vulkan.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        );
    // outline
    self.pipelines[1] = try self.create_pipeline(
        outline_vert_source,
        outline_frag_source,
        false,
        &generic_binding_description,
        @intCast(generic_binding_description.len),
        &generic_attribute_description,
        @intCast(generic_attribute_description.len),
        c.vulkan.VK_PRIMITIVE_TOPOLOGY_LINE_STRIP,
        );
    // simple chunk
    self.pipelines[2] = try self.create_pipeline(
        chunk_vert_source,
        chunk_frag_source,
        false,
        &chunk_binding_description,
        @intCast(chunk_binding_description.len),
        &chunk_attribute_description,
        @intCast(chunk_attribute_description.len),
        c.vulkan.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        );
    
    try self.create_framebuffers();
    try self.create_command_pool();
    try self.create_command_buffers();
    try self.create_sync_objects();

    // GLFW INIT
    c.vulkan.glfwSetWindowSizeLimits(self.window, 480, 270, c.vulkan.GLFW_DONT_CARE, c.vulkan.GLFW_DONT_CARE);

    // cursor
    try self.render_targets.append(
        self.allocator.*,
        .{ .vertex_index = 0, .pipeline_index = 0}
        );
    // outline
    try self.render_targets.append(
        self.allocator.*,
        .{ .vertex_index = 1, .pipeline_index = 1, .instance_count = 0}
        );
    
    try self.create_vertex_buffer(
        0,
        @sizeOf(Vertex),
        @intCast(cursor_vertices.len * @sizeOf(Vertex)),
        @ptrCast(@constCast(&cursor_vertices[0]))
        );
    try self.create_vertex_buffer(
        1,
        @sizeOf(Vertex),
        @intCast(block_selection_cube.len * @sizeOf(Vertex)),
        @ptrCast(@constCast(&block_selection_cube[0]))
        );

    // RENDER INIT

    const BufferInfo = struct {
        create_info: c.vulkan.VkBufferCreateInfo,
        alloc_info: c.vulkan.VmaAllocationCreateInfo,
    };

    const buffer_infos: [2]BufferInfo = .{
        .{  .create_info = .{
                .sType = c.vulkan.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .size = 500 * @sizeOf(zm.Mat),
                .usage = c.vulkan.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | c.vulkan.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            },
            .alloc_info = .{
                .usage = c.vulkan.VMA_MEMORY_USAGE_AUTO,
                .flags = c.vulkan.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
            },
        },
        .{  .create_info = .{
                .sType = c.vulkan.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .size = 256 * @sizeOf(ChunkRenderData),
                .usage = c.vulkan.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | c.vulkan.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            },
            .alloc_info = .{
                .usage = c.vulkan.VMA_MEMORY_USAGE_AUTO,
                .flags = c.vulkan.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
            },
        },
    };

    for (buffer_infos) |buffer| {
        var ubo: c.vulkan.VkBuffer = undefined;
        var alloc: c.vulkan.VmaAllocation = undefined;
        const buffer_success = c.vulkan.vmaCreateBuffer(self.vma_allocator, &buffer.create_info, &buffer.alloc_info, &ubo, &alloc, null);
        
        if (buffer_success != c.vulkan.VK_SUCCESS)
        {
            std.debug.print("success: {}\n", .{buffer_success});
            return VkAbstractionError.UBOBufferCreationFailure;
        }

        try self.ubo_buffers.append(self.allocator.*, ubo);
        try self.ubo_allocs.append(self.allocator.*, alloc);
    }

    var image_info0 = ImageInfo{
        .depth = 1,
        .subresource_range = .{
            .aspectMask = c.vulkan.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .views = try self.allocator.*.alloc(c.vulkan.VkImageView, self.MAX_CONCURRENT_FRAMES),
        .samplers = try self.allocator.*.alloc(c.vulkan.VkSampler, self.MAX_CONCURRENT_FRAMES),
    };
    defer self.allocator.*.free(image_info0.views);
    defer self.allocator.*.free(image_info0.samplers);
   
    const image_data0 = c.stb.stbi_load(
        "fortnite.jpg",
        &image_info0.width,
        &image_info0.height,
        &image_info0.channels,
        c.stb.STBI_rgb_alpha
        );
    if (image_data0 == null){
        std.debug.print("Unable to find image file \n", .{});
        return;
    }
    else
    {
        image_info0.data = image_data0;
    }

    try create_2d_texture(self, &image_info0);
    c.stb.stbi_image_free(image_info0.data);

    try create_image_view(self.device, &image_info0);
    try create_samplers(self, &image_info0, c.vulkan.VK_FILTER_LINEAR, c.vulkan.VK_SAMPLER_ADDRESS_MODE_REPEAT, true);
    
    var image_info1 = ImageInfo{
        .depth = 1,
        .subresource_range = .{
            .aspectMask = c.vulkan.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .views = try self.allocator.*.alloc(c.vulkan.VkImageView, self.MAX_CONCURRENT_FRAMES),
        .samplers = try self.allocator.*.alloc(c.vulkan.VkSampler, self.MAX_CONCURRENT_FRAMES),
    };
    defer self.allocator.*.free(image_info1.views);
    defer self.allocator.*.free(image_info1.samplers);
   
    const image_data1 = c.stb.stbi_load(
        "blocks.png",
        &image_info1.width,
        &image_info1.height,
        &image_info1.channels,
        c.stb.STBI_rgb_alpha
        );
    if (image_data1 == null){
        std.debug.print("Unable to find image file \n", .{});
        return;
    }
    else
    {
        image_info1.data = image_data1;
    }

    try create_2d_texture(self, &image_info1);
    c.stb.stbi_image_free(image_info1.data);

    try create_image_view(self.device, &image_info1);
    try create_samplers(self, &image_info1, c.vulkan.VK_FILTER_NEAREST, c.vulkan.VK_SAMPLER_ADDRESS_MODE_REPEAT, false);

    // Descriptor Sets
    
    const layouts: [2]c.vulkan.VkDescriptorSetLayout = .{self.descriptor_set_layout, self.descriptor_set_layout};
    const descriptor_alloc_info = c.vulkan.VkDescriptorSetAllocateInfo{
        .sType = c.vulkan.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = self.descriptor_pool,
        .descriptorSetCount = self.MAX_CONCURRENT_FRAMES,
        .pSetLayouts = &layouts,
    };

    if (c.vulkan.vkAllocateDescriptorSets(
            self.device,
            &descriptor_alloc_info,
            self.descriptor_sets.ptr
            ) != c.vulkan.VK_SUCCESS) {
        std.debug.print("Unable to allocate Descriptor Sets\n", .{});
    }
    
    for (0..self.MAX_CONCURRENT_FRAMES) |i| {
        const buffers: [2]c.vulkan.VkDescriptorBufferInfo = .{
            // Particles
            c.vulkan.VkDescriptorBufferInfo{
                .buffer = self.ubo_buffers.items[0],
                .offset = 0,
                .range = 500 * @sizeOf(zm.Mat),
            },
            // Chunks
            c.vulkan.VkDescriptorBufferInfo{
                .buffer = self.ubo_buffers.items[1],
                .offset = 0,
                .range = 256 * @sizeOf(ChunkRenderData),
            },
        };
        
        const images: [2]c.vulkan.VkDescriptorImageInfo = .{
            c.vulkan.VkDescriptorImageInfo{
                .imageLayout = c.vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                .imageView = image_info0.views[i],
                .sampler = image_info0.samplers[i],
            },
            c.vulkan.VkDescriptorImageInfo{
                .imageLayout = c.vulkan.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                .imageView = image_info1.views[i],
                .sampler = image_info1.samplers[i],
            }
        };

        const descriptor_writes: [4]c.vulkan.VkWriteDescriptorSet = .{
            c.vulkan.VkWriteDescriptorSet{
                .sType = c.vulkan.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.descriptor_sets[i],
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorType = c.vulkan.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = 1,
                .pBufferInfo = &buffers[0],
                .pImageInfo = null,
                .pTexelBufferView = null,
            },
            c.vulkan.VkWriteDescriptorSet{
                .sType = c.vulkan.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.descriptor_sets[i],
                .dstBinding = 1,
                .dstArrayElement = 0,
                .descriptorType = c.vulkan.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .pBufferInfo = null,
                .pImageInfo = &images[0],
                .pTexelBufferView = null,
            },
            c.vulkan.VkWriteDescriptorSet{
                .sType = c.vulkan.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.descriptor_sets[i],
                .dstBinding = 2,
                .dstArrayElement = 0,
                .descriptorType = c.vulkan.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .pBufferInfo = null,
                .pImageInfo = &images[1],
                .pTexelBufferView = null,
            },
            c.vulkan.VkWriteDescriptorSet{
                .sType = c.vulkan.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = self.descriptor_sets[i],
                .dstBinding = 3,
                .dstArrayElement = 0,
                .descriptorType = c.vulkan.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = 1,
                .pBufferInfo = &buffers[1],
                .pImageInfo = null,
                .pTexelBufferView = null,
            },
        };

        c.vulkan.vkUpdateDescriptorSets(self.device, descriptor_writes.len, &descriptor_writes, 0, null);
    }

    self.push_constant_data = try self.allocator.*.alloc(u8, self.PUSH_CONSTANT_SIZE);
    defer self.allocator.*.free(self.push_constant_data);
}

//                                                     ..::::------:::...                                                 
//                                             .:-=+*#######################*+=-:.                                        
//                                        .-+*#######*************+**********######*+=:.                                  
//                                    .-+#####****+++******************+++++++++++****###*=:                              
//                                 :=*###**++++*********++++++++++++++++++++++++++++++++**###+:                           
//                              :+###**+++++++++++++++++++++++++++++++++++++++++++++++++++++*###=:                        
//                           .=*##*++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*##*=.                     
//                         .+##*++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*##+.                   
//                       :+##*++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++==+*#=                  
//                     .+##*++++++++++++++++++++++++++++++++++++++++++++++++++=============+==========+**:                
//                    -*#*++++++++++++++++++++++++++++++=+++++==++========================-=============+#+               
//                  .=##+++++++++++++++======================================--============-==============**:             
//                 :*#*=+++=====================================--============:=============-=========--===*#-            
//                .*#+==========================================:-============--==-========-:-===-=====--===+#-           
//               .*#=============================-=============-:==--==========:==--========::-==-:=====:====+*-          
//               **=========================-:==-==============::==:===--==--==--==:-=======-::===--====--=====*-         
//              +#===================-=====-.:=--=============-.:=:-====:==-.==-:-=::-=======::-===:=====:=====+*:        
//             =#+================-=--=====:.:-:==============:.---=====:-=-.-=-.:=:.:-======---===--====--====-*+.       
//            :**===============-::::==-==-.:::-==============::::======:-=-.:-=..:-..:-=====--:-==-:--==-:====--*=       
//            +#===-===========-::::-=-:=-:.::.-=============-.::-====-=::=--.-=:..-:.::=====-::---=:-:-==--====:+*:      
//           .*+==-:==========::::.-=-::=:..:..-=--========-=-..:=-===-=.:=-+::---.:-.:.-=--=-:---:=:--:==--=--=-:*+.     
//           -*==-::========-::::.:==-.:-...:..:=-----------=:..-=----=-..--*:.--*:.-...:---=::---:=-:-.-=--=-=-=:=*-     
//           =*==-::=======-:.:::.-=-:.-:...:..:--:----------:..-----=-::.-=#-.:=#=.::.:.:=-=:::--:-- :.:=-:=---=--*=     
//           ++=-:::====-=-:.:...:=-:.::.......:--:----------:..------.==.:#%=.:#%*:.:.:.:---:::--.:. ::.--:=---=-.=*.    
//           =+=-:::=---=-:.:....-=-...........:--:----------...-----..=: :+=: .===:......---.:::- :-::..:-:-=::=-::+=    
//           =+-::::---=-:.::...:=-:............--.:--------- ..:---:.=+..+%#- +%%%+......:--.:::- :-+.:.:-:--:.--:.==    
//           ==-::.:----:.......--:.............:-.:--------:...---:.-%+.-@@%-.%@@@#:.-....-:.:.:-::-*.:=.:::::.-=: --    
//           :--::.:---:.......:-:..............:-.:---------...--:.:#%-.#@@%.+@%@@%-.+....-:...:--.*#.=*.:::::.:=: :-    
//           .--.:.:--:.:......-:................-..---------..:-:..*@* *@%@+-@@@%%@=:*:...:...::+-:@#.==..::...:=: ::    
//            -:.:.:-:....... ::.................:..:--------..::..+@@:=@%@%=%@%###%=+#:.......:-+.--.   .......:-: .:    
//            .:...::.........:.......... ..........:--------:....=@@==@%@%*##******+%%-.:. -:.::. ::+= ......:.:-:  :    
//            .:......................... ...........--------:...+@%*+@@@@%%%###**##%@%-...=*..=. .**%-.:.......:-. .:    
//             .........................   ..........:--------..+@@@%@@%%#*+=-:.  -*%@%-.:*%-:#@+.:.=%... ......:-.  .    
//             ........................    ...........:--:-:--:+@@#+=::.. :-==+**++#@@#.-#@*=%@@#=*-=+-.. ......::  .     
//             .......................     ...........:--:-::-:+=..  .....*@@+%@@@@@@@#*@@%%@@%@@%#*#%*.. ..... :.        
//             :.....................  -=-. ...........:-::-.:.:-. ::.:..::+--@@@@@@@@@@@@@@%@@@@@@@@@%: .......:         
//             ...................... =##**-............:-.-::--##+==--***+-.*#*+#@@@@@@@@@@@@@@#%@%%%@-...... .:         
//            .....................  .**=++-...... ......:::--:-#@%%#%##******#%%@@@@@@@@@@@@@@@%*%@@@@#:..... .          
//           .....................   :#*+*++:...... ........:+-:=@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%#*%@%@-...::            
//         ...    ................   :*#*+*#=.......... .....=*::#@%@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@%*@%@%:..:-:            
//               ....................:**##+==..... ..... .....#*:=@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@@@@+...--:            
//              ......................*#++=**-..... ..... ....=@#:+@%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@+...--:            
//             .......................:**==##*...... ..........#@#-#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@%:...--:            
//            .........................:+#++*#-............. ..-@@%+%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@-....--:            
//          ...........................  :+*+++.............:...*@@%%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%@=.....:-:            
//        ............     .............   .=+*=..........:.::...#@%@@@@@@@@@@@@@@@@@@@@@@@@%%%@@@%@=...:. :-.            
//                        ..............      :-..........:-.:-:.:#@%@@@@@@@@@@@@@@@@@@%%%%%%%@@%@@=...:-..::             
//                        ..............         ..........--:---=*%@@@@@@@@@@@@@@@@@@@%%%%%@@@@@@=....--..::             
//                       .....  ....:-..          .........:-----=@%@@@@@@@@@@@@@@@@@@@@@@##%@@@@=....:-:..::             
//                       ..     ...: :.            ..-......-:---:*%%@@@@@@@@@@@@@@@@@@@@@@@@@%@= ....:-:  .              
//                      ..     ...:  :.            ..=-.....::-----**##%%@@@@@@@@@@@@@@@@@@@@%@+......--:  .              
//                      .      ...   :..:        -:  -*.....:.:----*++++**#%%%@@@@@@%%%%%%%%%@*......:--. .               
//                            ..     :.-.       :#-..:#-......::.--###****+==+**##%%%@@@@@@@@%.......:-:  :               
//                            .      :.-.   -. .*#--=:#*:.....:-:::*######+.    ..:-=+++***#*:.......::. ..               
//                                   =-:.  == .*##-+*-*#+......:=-:*###*#+:                 .........::                   
//                                   : .  =#..*##**##+**#-.....:+=:*####*=                  .........:.                   
//                                     . -#+-%@%%%#*###*#+.....:++.*##*#+.                  .........:                    
//                                   .:::*%%@@%%%@%%#*##*#-.....+*:*###*-                    . .....:.                    
//                                  .=+=*%@@%%%%%%%@%#*#*#+....:**+*###+=-.                  . .....:                     
//                                  =**=#@%%%%%%%%%%@%#*##*: ..-#######=+*+=---.             .:....:.                     
//                                .=****+%@%@@%%%%%%%@@%#*#- ..=#**#*#*=*++****+-:=*=-+++****:=-....                      
//                               :+#*+**#+%@%@%%%%%%%%@@%##+ ..*####*#+*#**++****+--*##%@@@@@+** . :                      
//                             .=+=*%++*##*%@%@@@@@%%%@%@@%*. -#*#####=*#%%#*++***#+:-###%@%%%%%.  #*.                    
//                           :+#@@*=#%++###*#@%@@@@@@@@@@@@%-.*######***#@@%%#*+***##=:+##%@%@%@= +@@#:                   
//                       :=-:=%@%%%*=#%=+##%*#@@@@@@@@@@@@%%:=%***#####*%@%@@%%#*++*#%#=-*##%@%@*=@%%@%-                  
//                    :-*##*+-:+%@@%*=#%=*%#%**@@%@@@@@@@%@#=@%%##***###%@%%%%@@%%#*+*%%*-=**#@%%%%%%%@%-                 
//               :-+*#%%@@@%#*=--+%@%*=##+#%#%**%@%@@@@@@@@%%@%@@%%##**#%%%%%%%%@@%*+**#%%+-+*#%@@%%%%%%%-                
//           :=*#%%@@@%%%%%@@%#*=-:+%@#+##*%##%#+#@%%@@@%%%@@%%%%%@%%%#%@%%%%%@@%#+*%@%#*#%#=+**%#%@%%%%@#:               
//       .-*#%@@@%%%%%%%%%%%%%@%#*=:-*%#+#%####%#**@@%%@@@@@@@@@@@%%@@@@@%%%%%%#++%@%%%@%**#%*****+@%%%%%@*               
//     .+#%@@%%%%%%%%%%%%%%%%%%%@%*+-:-##+*%#####%*+%@%###%%%%%%%%%%%%%%%%%%%#*##%@%%%%%@@#++#%#*+-+@%%%%%@+              
//    -#@%%%%%%%%%%%%%%%%%%%%%%%%@%#*+-:=*+*%#####%#+#@%%%#################%%%%%@%%%%%%%%%@%*+*###*-+%@@%%%@=             
//   =%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@%**=:-==*######%#**@@@@@@@%%%%@@@@@@@%%%%@@%%%%%%%%%%%%%@#++####++##****%-
//
//  :D
