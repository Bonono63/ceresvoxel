//Proceeds to zig all over the place...
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");
const zm = @import("zmath");
const meshers = @import("mesh_generation.zig");

const ENGINE_NAME = "CeresVoxel";

var xpos: f64 = 0.0;
var ypos: f64 = 0.0;
var dx: f64 = 0.0;
var dy: f64 = 0.0;

const Inputs = packed struct {
    w : bool = false,
    a : bool = false,
    s : bool = false,
    d : bool = false,
    space : bool = false,
    shift : bool = false,
    control : bool = false,
    mouse_capture : bool = true
};

var inputs = Inputs{};

const PlayerState = struct {
    pos : @Vector(3, f32) = .{ 0.0, 0.0, -1.0 },
    yaw : f32 = std.math.pi/2.0,
    pitch : f32 = 0.0,
    look : zm.Vec = .{ 0.0, 0.0, 0.0, 1.0 },
};

var player_state = PlayerState{};

const MAX_CONCURRENT_FRAMES = 2;

pub fn main() !void {
    // ZIG INIT
    std.debug.print("[Info] Runtime Safety: {}\n", .{std.debug.runtime_safety});

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const heap_status = gpa.deinit();
        if (std.debug.runtime_safety)
            std.debug.print("[Info] Memory leaked during runtime: {}\n", .{heap_status});
    }

    var allocator = arena.allocator();

    if (std.debug.runtime_safety)
    {
        allocator = gpa.allocator();
    }

    // VULKAN INIT
    var instance = vulkan.Instance{ .allocator = &allocator, .MAX_CONCURRENT_FRAMES = MAX_CONCURRENT_FRAMES };

    instance.shader_modules = std.ArrayList(c.VkShaderModule).init(instance.allocator.*);
    defer instance.shader_modules.deinit();

    instance.command_buffers = try instance.allocator.*.alloc(c.VkCommandBuffer, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.command_buffers);

    instance.descriptor_sets = try instance.allocator.*.alloc(c.VkDescriptorSet, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.descriptor_sets);

    instance.image_available_semaphores = try instance.allocator.*.alloc(c.VkSemaphore, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.image_available_semaphores);
    instance.image_completion_semaphores = try instance.allocator.*.alloc(c.VkSemaphore, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.image_completion_semaphores);
    instance.in_flight_fences = try instance.allocator.*.alloc(c.VkFence, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.in_flight_fences);

    try vulkan.glfw_initialization();
    try instance.window_setup(ENGINE_NAME, ENGINE_NAME);

    const vulkan_functions = c.VmaVulkanFunctions{
        .vkGetInstanceProcAddr = &c.vkGetInstanceProcAddr,
        .vkGetDeviceProcAddr = &c.vkGetDeviceProcAddr,
    };

    try instance.create_surface();
    try instance.pick_physical_device();
    c.vkGetPhysicalDeviceMemoryProperties(instance.physical_device, &instance.mem_properties);
    try instance.create_present_queue(instance.REQUIRE_FAMILIES);
    try instance.create_swapchain();
    try instance.create_swapchain_image_views();
    try instance.create_descriptor_pool();

    try instance.create_descriptor_set_layouts();

    const vma_allocator_create_info = c.VmaAllocatorCreateInfo{
        .flags = c.VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT,
        .vulkanApiVersion = c.VK_API_VERSION_1_2,
        .physicalDevice = instance.physical_device,
        .device = instance.device,
        .instance = instance.vk_instance,
        .pVulkanFunctions = &vulkan_functions,
    };
    
    //var vma_allocator : c.VmaAllocator = undefined;
    const vma_allocator_success = c.vmaCreateAllocator(&vma_allocator_create_info, &instance.vma_allocator);

    if (vma_allocator_success != c.VK_SUCCESS)
    {
        std.debug.print("Unable to create vma allocator {}\n", .{vma_allocator_success});
    }

    try instance.create_depth_resources();

    try instance.create_graphics_pipeline();
    try instance.create_framebuffers();
    try instance.create_command_pool();
    try instance.create_command_buffers();
    try instance.create_sync_objects();

    // GLFW INIT
    _ = c.glfwSetKeyCallback(instance.window, key_callback);

    _ = c.glfwSetCursorPosCallback(instance.window, cursor_pos_callback);
    _ = c.glfwSetWindowUserPointer(instance.window, &instance);
    _ = c.glfwSetFramebufferSizeCallback(instance.window, window_resize_callback);

    c.glfwSetWindowSizeLimits(instance.window, 240, 135, c.GLFW_DONT_CARE, c.GLFW_DONT_CARE);

    const random = std.crypto.random; 

    var chunk_data : [32768]u8 = undefined;
    for (0..32768) |i|
    {
        const val = random.int(u1);
        if (val == 0)
        {
            chunk_data[i] = val;
        }
    }

    const chunk_mesh_start_time : f64 = c.glfwGetTime();
    const vertices : std.ArrayList(vulkan.Vertex) = try meshers.basic_mesh(instance.allocator, &chunk_data);
    defer vertices.deinit();

    std.debug.print("chunk mesh time: {d:.3}ms\n", .{ (c.glfwGetTime() - chunk_mesh_start_time) * 1000.0 });
    
    // RENDER INIT

    instance.vertex_buffers = try instance.allocator.*.alloc(c.VkBuffer, 1);
    defer instance.allocator.*.free(instance.vertex_buffers);
    instance.vertex_allocs = try instance.allocator.*.alloc(c.VmaAllocation, 1);
    defer instance.allocator.*.free(instance.vertex_allocs);

    var vertex_buffer : c.VkBuffer = undefined;

    const vertices_size = vertices.items.len * @sizeOf(vulkan.Vertex);

    var vertex_buffer_create_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = vertices_size,
        .usage = c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT
    }; 

    const vertex_alloc_create_info = c.VmaAllocationCreateInfo{
        .usage = c.VMA_MEMORY_USAGE_AUTO,
        .flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
    };

    _ = c.vmaCreateBuffer(instance.vma_allocator, &vertex_buffer_create_info, &vertex_alloc_create_info, &vertex_buffer, &instance.vertex_allocs[0], null);

    _ = c.vmaCopyMemoryToAllocation(instance.vma_allocator, vertices.items.ptr, instance.vertex_allocs[0], 0, vertices_size);

    instance.vertex_buffers[0] = vertex_buffer;

    const ObjectTransform = struct {
        model: zm.Mat = zm.identity(),
        view: zm.Mat = zm.identity(),
        projection: zm.Mat = zm.identity(),
    };
    
    var object_transform = ObjectTransform{};
    
    _ = &object_transform;
    
    var ubo_buffers : [MAX_CONCURRENT_FRAMES]c.VkBuffer = undefined;

    const ubo_buffer_create_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = @sizeOf(ObjectTransform),
        .usage = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
    };

    const ubo_alloc_create_info = c.VmaAllocationCreateInfo{
        .usage = c.VMA_MEMORY_USAGE_AUTO,
        .flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
    };

    var ubo_alloc : [MAX_CONCURRENT_FRAMES]c.VmaAllocation = undefined;
    for (0..MAX_CONCURRENT_FRAMES) |i|
    {
        _ = c.vmaCreateBuffer(instance.vma_allocator, &ubo_buffer_create_info, &ubo_alloc_create_info, &ubo_buffers[i], &ubo_alloc[i], null);

        _ = c.vmaCopyMemoryToAllocation(instance.vma_allocator, &object_transform, ubo_alloc[i], 0, @sizeOf(ObjectTransform));
    }

    var image_info0 = vulkan.ImageInfo{
        .depth = 1,
        .subresource_range = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .views = try instance.allocator.*.alloc(c.VkImageView, MAX_CONCURRENT_FRAMES),
        .samplers = try instance.allocator.*.alloc(c.VkSampler, MAX_CONCURRENT_FRAMES),
    };
    defer instance.allocator.*.free(image_info0.views);
    defer instance.allocator.*.free(image_info0.samplers);
   
    // TODO turn this into a one line conditional
    const image_data = c.stbi_load("fortnite.jpg", &image_info0.width, &image_info0.height, &image_info0.channels, c.STBI_rgb_alpha);
    if (image_data == null){
        std.debug.print("Unable to find image file \n", .{});
        return;
    }
    else
    {
        image_info0.data = image_data;
    }

    try vulkan.create_2d_texture(&instance, &image_info0);

    try vulkan.create_image_view(instance.device, &image_info0);
    try vulkan.create_samplers(&instance, &image_info0, c.VK_FILTER_LINEAR, c.VK_SAMPLER_ADDRESS_MODE_REPEAT);

    // Depth Image
    
    

    // Descriptor Sets

    const layouts : [2]c.VkDescriptorSetLayout = .{instance.descriptor_set_layout, instance.descriptor_set_layout};

    const descriptor_alloc_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = instance.descriptor_pool,
        .descriptorSetCount = MAX_CONCURRENT_FRAMES,
        .pSetLayouts = &layouts,
    };

    if (c.vkAllocateDescriptorSets(instance.device, &descriptor_alloc_info, instance.descriptor_sets.ptr) != c.VK_SUCCESS) {
        std.debug.print("Unable to allocate Descriptor Sets\n", .{});
    }
    
    for (0..MAX_CONCURRENT_FRAMES) |i| {
        const buffer_info = c.VkDescriptorBufferInfo{
            .buffer = ubo_buffers[i],
            .offset = 0,
            .range = @sizeOf(ObjectTransform),
        };

        const image_info = c.VkDescriptorImageInfo{
            .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = image_info0.views[i],
            .sampler = image_info0.samplers[i],
        };

        const ubo_descriptor_write = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = instance.descriptor_sets[i],
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1,
            .pBufferInfo = &buffer_info,
            .pImageInfo = null,
            .pTexelBufferView = null,
        };
        
        const image_descriptor_write = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = instance.descriptor_sets[i],
            .dstBinding = 1,
            .dstArrayElement = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .pBufferInfo = null,
            .pImageInfo = &image_info,
            .pTexelBufferView = null,
        };

        const descriptor_writes: [2]c.VkWriteDescriptorSet = .{ubo_descriptor_write, image_descriptor_write};

        c.vkUpdateDescriptorSets(instance.device, descriptor_writes.len, &descriptor_writes, 0, null);
    }

    // FRAME LOOP

    var frame_count: u64 = 0;
    var current_frame_index: u32 = 0;
    var previous_frame_time: f32 = 0.0;

    var window_height : i32 = 0;
    var window_width : i32 = 0;
    
    while (c.glfwWindowShouldClose(instance.window) == 0) {
        c.glfwPollEvents();

        const current_time : f32 = @floatCast(c.glfwGetTime());
        const frame_delta: f32 = current_time - previous_frame_time;
        previous_frame_time = current_time;

        c.glfwGetWindowSize(instance.window, &window_width, &window_height);
        const aspect_ratio : f32 = @as(f32, @floatFromInt(window_width))/@as(f32, @floatFromInt(window_height));

        if (inputs.mouse_capture)
        {
            c.glfwSetInputMode(instance.window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
        }
        else
        {
            c.glfwSetInputMode(instance.window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
        }

        player_state.look[0] = player_state.look[0] + @as(f32, @floatCast(std.math.cos(player_state.yaw)));
        player_state.look[1] = player_state.look[1] + @as(f32, @floatCast(std.math.sin(player_state.pitch)));
        player_state.look[2] = player_state.look[2] + @as(f32, @floatCast(std.math.sin(player_state.yaw)));
        player_state.look = zm.normalize3(player_state.look);

        object_transform.view = zm.lookToLh(.{player_state.pos[0], player_state.pos[1], player_state.pos[2], 1.0}, player_state.look, .{ 0.0, 1.0, 0.0, 1.0});
        object_transform.projection = zm.perspectiveFovLh(1.0, aspect_ratio, 0.1, 1000.0);
        
        var speed : f32 = 1.0;
        if (inputs.control)
        {
            speed = 5.0;
        }

        // TODO Make this the center of gravitational wells and such
        const up : zm.Vec = .{ 0.0, -1.0, 0.0, 1.0 };
        const right = zm.cross3(player_state.look, up);
        const forward = zm.cross3(right, up);
        if (inputs.space)
        {
            player_state.pos += .{ up[0] * frame_delta * speed, up[1] * frame_delta * speed, up[2] * frame_delta * speed };
        }
        if (inputs.shift)
        {
            player_state.pos -= .{ up[0] * frame_delta * speed, up[1] * frame_delta * speed, up[2] * frame_delta * speed };
        }
        if (inputs.a)
        {
            player_state.pos -= .{ right[0] * frame_delta * speed, right[1] * frame_delta * speed, right[2] * frame_delta * speed };
        }
        if (inputs.d)
        {
            player_state.pos += .{ right[0] * frame_delta * speed, right[1] * frame_delta * speed, right[2] * frame_delta * speed };
        }
        if (inputs.w)
        {
            player_state.pos -= .{ forward[0] * frame_delta * speed, forward[1] * frame_delta * speed, forward[2] * frame_delta * speed };
        }
        if (inputs.s)
        {
            player_state.pos += .{ forward[0] * frame_delta * speed, forward[1] * frame_delta * speed, forward[2] * frame_delta * speed };
        }

        std.debug.print("\t{s} pos:{d:.1} {d:.1} {d:.1} y:{d:.1} p:{d:.1} {d:.3}ms \r", .{
            if (inputs.mouse_capture) "on " else "off",
            player_state.pos[0], 
            player_state.pos[1],
            player_state.pos[2],
            player_state.yaw,
            player_state.pitch,
            frame_delta * 1000.0,
        });

        _ = c.vmaCopyMemoryToAllocation(instance.vma_allocator, &object_transform, ubo_alloc[current_frame_index], 0, @sizeOf(ObjectTransform));

        try instance.draw_frame(current_frame_index, &instance.vertex_buffers, @intCast(vertices.items.len));

        current_frame_index = (current_frame_index + 1) % instance.MAX_CONCURRENT_FRAMES;
        frame_count += 1;
    }

    // CLEANUP

    _ = c.vkDeviceWaitIdle(instance.device);

    vulkan.image_cleanup(&instance, &image_info0);
    for (0..MAX_CONCURRENT_FRAMES) |i| {
        c.vmaDestroyBuffer(instance.vma_allocator, ubo_buffers[i], ubo_alloc[i]);
    }
    instance.cleanup();
}

pub fn key_callback(window: ?*c.GLFWwindow, key: i32, scancode: i32, action: i32, mods: i32) callconv(.C) void {
    _ = &scancode;
    _ = &action;
    _ = &mods;

    switch (key) {
        c.GLFW_KEY_ESCAPE => {
            c.glfwSetWindowShouldClose(window, c.GLFW_TRUE);
        },
        c.GLFW_KEY_LEFT_CONTROL => {
            if (action == c.GLFW_PRESS) {
                inputs.control = true;
            }
            if (action == c.GLFW_RELEASE) {
                inputs.control = false;
            }
        },
        c.GLFW_KEY_SPACE => {
            if (action == c.GLFW_PRESS) {
                inputs.space = true;
            }
            if (action == c.GLFW_RELEASE) {
                inputs.space = false;
            }
        },
        c.GLFW_KEY_LEFT_SHIFT => {
            if (action == c.GLFW_PRESS) {
                inputs.shift = true;
            }
            if (action == c.GLFW_RELEASE) {
                inputs.shift = false;
            }
        },
        c.GLFW_KEY_W => {
            if (action == c.GLFW_PRESS) {
                inputs.w = true;
            }
            if (action == c.GLFW_RELEASE) {
                inputs.w = false;
            }
        },
        c.GLFW_KEY_A => {
            if (action == c.GLFW_PRESS) {
                inputs.a = true;
            }
            if (action == c.GLFW_RELEASE) {
                inputs.a = false;
            }
        },
        c.GLFW_KEY_S => {
            if (action == c.GLFW_PRESS) {
                inputs.s = true;
            }
            if (action == c.GLFW_RELEASE) {
                inputs.s = false;
            }
        },
        c.GLFW_KEY_D => {
            if (action == c.GLFW_PRESS) {
                inputs.d = true;
            }
            if (action == c.GLFW_RELEASE) {
                inputs.d = false;
            }
        },
        c.GLFW_KEY_T => {
            if (action == c.GLFW_RELEASE) {
                if (inputs.mouse_capture == true)
                {
                    inputs.mouse_capture = false;
                }
                else
                {
                    inputs.mouse_capture = true;
                }
            }
        },
        else => {},
    }
}

pub fn cursor_pos_callback(window: ?*c.GLFWwindow, _xpos: f64, _ypos: f64) callconv(.C) void {
    const MOUSE_SENSITIVITY : f64 = 0.1;
    _ = &window;
    dx = _xpos - xpos;
    dy = _ypos - ypos;

    xpos = _xpos;
    ypos = _ypos;

    if (inputs.mouse_capture)
    {
        player_state.yaw -= @as(f32, @floatCast(dx * std.math.pi / 180.0 * MOUSE_SENSITIVITY));
        player_state.pitch += @as(f32, @floatCast(dy * std.math.pi / 180.0 * MOUSE_SENSITIVITY));
    }
}

pub fn window_resize_callback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    _ = &width;
    _ = &height;
    const instance: *vulkan.Instance = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));
    instance.framebuffer_resized = true;
}
