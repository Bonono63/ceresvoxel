//Proceeds to zig all over the place...
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");

const ENGINE_NAME = "CeresVoxel";

var xpos: f64 = 0.0;
var ypos: f64 = 0.0;
var w: bool = false;

const MAX_CONCURRENT_FRAMES = 2;

pub fn main() !void {
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

    var instance = vulkan.Instance{ .allocator = &allocator, .MAX_CONCURRENT_FRAMES = MAX_CONCURRENT_FRAMES };

    instance.shader_modules = std.ArrayList(c.VkShaderModule).init(instance.allocator.*);
    defer instance.shader_modules.deinit();

    instance.device_memory_allocations = std.ArrayList(c.VkDeviceMemory).init(instance.allocator.*);
    defer instance.device_memory_allocations.deinit();

    instance.command_buffers = try instance.allocator.*.alloc(c.VkCommandBuffer, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.command_buffers);

    instance.descriptor_sets = try instance.allocator.*.alloc(c.VkDescriptorSet, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.descriptor_sets);

    // One set per frame
    //instance.descriptor_set_layouts = try instance.allocator.*.alloc(c.VkDescriptorSetLayout, 2);
    //defer instance.allocator.*.free(instance.descriptor_set_layouts);

    instance.image_available_semaphores = try instance.allocator.*.alloc(c.VkSemaphore, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.image_available_semaphores);
    instance.image_completion_semaphores = try instance.allocator.*.alloc(c.VkSemaphore, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.image_completion_semaphores);
    instance.in_flight_fences = try instance.allocator.*.alloc(c.VkFence, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.in_flight_fences);

    try vulkan.glfw_initialization();
    try instance.window_setup(ENGINE_NAME, ENGINE_NAME);
    try instance.create_surface();
    try instance.pick_physical_device();
    c.vkGetPhysicalDeviceMemoryProperties(instance.physical_device, &instance.mem_properties);
    try instance.create_present_queue(instance.REQUIRE_FAMILIES);
    try instance.create_swapchain();
    try instance.create_swapchain_image_views();
    try instance.create_descriptor_pool();

    try instance.create_descriptor_set_layouts();

    try instance.create_graphics_pipeline();
    try instance.create_framebuffers();
    try instance.create_command_pool();
    try instance.create_command_buffers();
    try instance.create_sync_objects();

    _ = c.glfwSetKeyCallback(instance.window, key_callback);

    _ = c.glfwSetCursorPosCallback(instance.window, cursor_pos_callback);
    _ = c.glfwSetWindowUserPointer(instance.window, &instance);
    _ = c.glfwSetFramebufferSizeCallback(instance.window, window_resize_callback);

    const vertices: [6]vulkan.Vertex = .{
        .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1.0, 1.0, 1.0 } },
        .{ .pos = .{ 0.5, -0.5 }, .color = .{ 0.0, 1.0, 0.0 } },
        .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0.0, 0.0, 1.0 } },

        .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0.0, 0.0, 1.0 } },
        .{ .pos = .{ -0.5, 0.5 }, .color = .{ 1.0, 0.0, 0.0 } },
        .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1.0, 1.0, 1.0 } },
    };

    var vertex_device_memory: c.VkDeviceMemory = undefined;

    var vertex_buffers = try instance.allocator.*.alloc(c.VkBuffer, 1);
    defer instance.allocator.*.free(vertex_buffers);

    const buffer_size: u64 = try instance.createBuffer(vertices.len * @sizeOf(vulkan.Vertex), c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &vertex_buffers[0], &vertex_device_memory);

    // We copy the data over once?
    var vertex_mmio: ?*anyopaque = undefined;
    if (c.vkMapMemory(instance.device, vertex_device_memory, 0, buffer_size, 0, &vertex_mmio) != c.VK_SUCCESS) {
        std.debug.print("Unable to map device memory to CPU memory\n", .{});
        return;
    } else {
        @memcpy(@as([*]vulkan.Vertex, @ptrCast(@alignCast(vertex_mmio))), &vertices);
    }
    
    //const MAT4_IDENTITY = .{
    //    .{ 1.0, 0.0, 0.0, 0.0 },
    //    .{ 0.0, 1.0, 0.0, 0.0 },
    //    .{ 0.0, 0.0, 1.0, 0.0 },
    //    .{ 0.0, 0.0, 0.0, 1.0 },
    //};

    const MAT4_IDENTITY = .{
        .{ 0xAAAAAAAA, 0xAAAAAAAA, 0xAAAAAAAA, 0xAAAAAAAA },
        .{ 0xAAAAAAAA, 0xAAAAAAAA, 0xAAAAAAAA, 0xAAAAAAAA },
        .{ 0xAAAAAAAA, 0xAAAAAAAA, 0xAAAAAAAA, 0xAAAAAAAA },
        .{ 0xAAAAAAAA, 0xAAAAAAAA, 0xAAAAAAAA, 0xAAAAAAAA },
    };
    
    const ObjectTransform = struct {
        model: c.mat4 = MAT4_IDENTITY,
        view: c.mat4 = MAT4_IDENTITY,
        projection: c.mat4 = MAT4_IDENTITY,
    };
    
    var object_transform = ObjectTransform{};
    
    std.debug.print("object transform content: {any}\n", .{@as([*]u8, @ptrCast(@alignCast(&object_transform)))[0..@sizeOf(ObjectTransform)]});

    _ = &object_transform;
    
    //c.glm_perspective(3.14, 800.0/600.0, 0.001, 1000, @as([*c][4]f32, @ptrCast(@alignCast(&object_transform.projection))));
    
    //var temp: [1]ObjectTransform = .{object_transform};

    var ubo_buffers: [MAX_CONCURRENT_FRAMES]c.VkBuffer = undefined;

    var ubo_device_memory: [MAX_CONCURRENT_FRAMES]c.VkDeviceMemory = undefined;
    var ubo_mmio: [MAX_CONCURRENT_FRAMES]?*anyopaque = .{null, null};


    _ = try instance.createBuffer(@sizeOf(ObjectTransform), c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &ubo_buffers[0], &ubo_device_memory[0]);

    //for (0..MAX_CONCURRENT_FRAMES) |i| {
        const size0 = try instance.createBuffer(@sizeOf(ObjectTransform), c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &ubo_buffers[0], &ubo_device_memory[0]);

        if (c.vkMapMemory(instance.device, ubo_device_memory[0], 0, size0, 0, &ubo_mmio[0]) != c.VK_SUCCESS) {
            std.debug.print("Unable to map device memory to CPU memory\n", .{});
        } 
        @memcpy(@as([*]u8, @ptrCast(@alignCast(&ubo_mmio[0])))[0..@sizeOf(ObjectTransform)], @as([*]u8, @ptrCast(@alignCast(&object_transform)))[0..@sizeOf(ObjectTransform)]);


        const size1 = try instance.createBuffer(@sizeOf(ObjectTransform), c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &ubo_buffers[1], &ubo_device_memory[1]);

        if (c.vkMapMemory(instance.device, ubo_device_memory[1], 0, size1, 0, &ubo_mmio[1]) != c.VK_SUCCESS) {
            std.debug.print("Unable to map device memory to CPU memory\n", .{});
        } 
        @memcpy(@as([*]u8, @ptrCast(@alignCast(&ubo_mmio[1])))[0..@sizeOf(ObjectTransform)], @as([*]u8, @ptrCast(@alignCast(&object_transform)))[0..@sizeOf(ObjectTransform)]);
        //c.vkUnmapMemory(instance.device, ubo_device_memory[i]);
    //}

    std.debug.print("vertex mmio {*}\n", .{vertex_mmio});
    std.debug.print("ubo mmio {*}\n", .{ubo_mmio[0]});
    std.debug.print("ubo mmio {*}\n", .{ubo_mmio[1]});

    const layouts : [2]c.VkDescriptorSetLayout = .{instance.descriptor_set_layout, instance.descriptor_set_layout};

    const alloc_info = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = instance.descriptor_pool,
        .descriptorSetCount = MAX_CONCURRENT_FRAMES,
        .pSetLayouts = &layouts,
    };

    if (c.vkAllocateDescriptorSets(instance.device, &alloc_info, instance.descriptor_sets.ptr) != c.VK_SUCCESS) {
        std.debug.print("Unable to allocate Descriptor Sets\n", .{});
    }
    
    for (0..MAX_CONCURRENT_FRAMES) |i| {
        const buffer_info = c.VkDescriptorBufferInfo{
            .buffer = ubo_buffers[i],
            .offset = 0,
            .range = @sizeOf(ObjectTransform),
        };

        const descriptor_write = c.VkWriteDescriptorSet{
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

        c.vkUpdateDescriptorSets(instance.device, 1, &descriptor_write, 0, null);
    }

    var frame_count: u64 = 0;
    var current_frame_index: u32 = 0;

    var previous_frame_time: f64 = 0.0;

    std.debug.print("sizeof of {}\n", .{@sizeOf(ObjectTransform)});

    @memset(@as([*]u8, @ptrCast(@alignCast(&ubo_mmio[0])))[0..@sizeOf(ObjectTransform)], 0);
    @memset(@as([*]u8, @ptrCast(@alignCast(&ubo_mmio[1])))[0..@sizeOf(ObjectTransform)], 0);
    
    @memcpy(@as([*]u8, @ptrCast(@alignCast(&ubo_mmio[0])))[0..@sizeOf(ObjectTransform)], @as([*]u8, @ptrCast(@alignCast(&object_transform)))[0..@sizeOf(ObjectTransform)]);
    
    std.debug.print("object transform content: {any}\n", .{@as([*]u8, @ptrCast(@alignCast(&ubo_mmio[0])))[0..@sizeOf(ObjectTransform)]});
    std.debug.print("object transform content: {any}\n", .{@as([*]u8, @ptrCast(@alignCast(&ubo_mmio[1])))[0..@sizeOf(ObjectTransform)]});


    //std.debug.print("object transform content: {any}\n", .{@as([*]f32, @ptrCast(@alignCast(&ubo_mmio[0])))[0..48]});
    //@memcpy(@as([*]u8, @ptrCast(@alignCast(&ubo_mmio[0])))[0..192], @as([*]u8, @ptrCast(@alignCast(&temp)))[0..192]);
    //std.debug.print("object transform content: {any}\n", .{@as([*]f32, @ptrCast(@alignCast(&ubo_mmio[0])))[0..48]});
    
    while (c.glfwWindowShouldClose(instance.window) == 0) {
        c.glfwPollEvents();

        const current_time = c.glfwGetTime();
        const frame_delta: f64 = current_time - previous_frame_time;
        previous_frame_time = current_time;

        std.debug.print("\tw: {:5} x: {d:.2} y: {d:.2} {d:.3}ms   \r", .{ w, xpos, ypos, (frame_delta * 1000.0)});

        //temp[0].model[0][0] = std.math.sin(0.01 * @as(f32, @floatFromInt(frame_count % 4712)));

    //std.debug.print("object transform content: {any}\n", .{@as([*]f32, @ptrCast(@alignCast(&ubo_mmio[1])))[0..48]});
        //@memcpy(@as([*]u8, @ptrCast(@alignCast(&ubo_mmio[current_frame_index])))[0..192], @as([*]u8, @ptrCast(@alignCast(&temp)))[0..192]);

        try instance.draw_frame(current_frame_index, vertex_buffers, vertices.len);

        current_frame_index = (current_frame_index + 1) % instance.MAX_CONCURRENT_FRAMES;
        frame_count += 1;
    }

    c.vkUnmapMemory(instance.device, vertex_device_memory);

    _ = c.vkDeviceWaitIdle(instance.device);
    c.vkFreeMemory(instance.device, vertex_device_memory, null);
    for (0..MAX_CONCURRENT_FRAMES) |i| {
        c.vkDestroyBuffer(instance.device, ubo_buffers[i], null);
        c.vkFreeMemory(instance.device, ubo_device_memory[i], null);
    }
    for (vertex_buffers) |buffer| {
        c.vkDestroyBuffer(instance.device, buffer, null);
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
        c.GLFW_KEY_W => {
            if (action == c.GLFW_PRESS) {
                w = true;
            }
            if (action == c.GLFW_RELEASE) {
                w = false;
            }
        },
        else => {},
    }
}

pub fn cursor_pos_callback(window: ?*c.GLFWwindow, _xpos: f64, _ypos: f64) callconv(.C) void {
    _ = &window;
    xpos = _xpos;
    ypos = _ypos;
}

pub fn window_resize_callback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    _ = &width;
    _ = &height;
    const instance: *vulkan.Instance = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));
    instance.framebuffer_resized = true;
}
