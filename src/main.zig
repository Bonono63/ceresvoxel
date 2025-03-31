//Proceeds to zig all over the place...
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");

const ENGINE_NAME = "CeresVoxel";

var xpos: f64 = 0.0;
var ypos: f64 = 0.0;
var w: bool = false;

pub fn main() !void {
    std.debug.print("Runtime Safety: {}\n", .{std.debug.runtime_safety});

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    const allocator = arena.allocator();

    // TODO: use gpa/debug allocator if runtime safety is enabled
    //    if (std.debug.runtime_safety)
    //    {
    //
    //        allocator.
    //    }

    var instance = vulkan.Instance{ .allocator = &allocator, .MAX_CONCURRENT_FRAMES = 2 };

    instance.shader_modules = std.ArrayList(c.VkShaderModule).init(instance.allocator.*);
    defer instance.shader_modules.deinit();

    instance.device_memory_allocations = std.ArrayList(c.VkDeviceMemory).init(instance.allocator.*);
    defer instance.device_memory_allocations.deinit();

    instance.command_buffers = try instance.allocator.*.alloc(c.VkCommandBuffer, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.command_buffers);

    instance.image_available_semaphores = try instance.allocator.*.alloc(c.VkSemaphore, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.image_available_semaphores);
    instance.image_completion_semaphores = try instance.allocator.*.alloc(c.VkSemaphore, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.image_completion_semaphores);
    instance.in_flight_fences = try instance.allocator.*.alloc(c.VkFence, instance.MAX_CONCURRENT_FRAMES);
    defer instance.allocator.*.free(instance.in_flight_fences);

    try instance.initialize_state(ENGINE_NAME, ENGINE_NAME);

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

    instance.vertex_buffers = try instance.allocator.*.alloc(c.VkBuffer, 1);
    defer allocator.free(instance.vertex_buffers);

    //    var vertex_buffer: c.VkBuffer = undefined;
    var vertex_device_memory: c.VkDeviceMemory = undefined;

    const buffer_size: u64 = try instance.createBuffer(vertices.len * @sizeOf(vulkan.Vertex), c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &instance.vertex_buffers[0], &vertex_device_memory);

    // We copy the data over once?
    var vertex_mmio: ?*anyopaque = undefined;
    if (c.vkMapMemory(instance.device, vertex_device_memory, 0, buffer_size, 0, &vertex_mmio) != c.VK_SUCCESS) {
        std.debug.print("Unable to map device memory to CPU memory\n", .{});
    } else {
        @memcpy(@as([*]vulkan.Vertex, @ptrCast(@alignCast(vertex_mmio))), &vertices);
        c.vkUnmapMemory(instance.device, vertex_device_memory);
    }

    //const object_transform = struct {
    //    model : c.mat4,
    //    view : c.mat4,
    //    projection : c.mat4,
    //};
    //
    //var ubo_buffers : [instance.MAX_CONCURRENT_FRAMES]c.VkBuffer = undefined;
    //const device_size :[instance.MAX_CONCURRENT_FRAMES]c.VkDeviceSize = @sizeOf(object_transform);

    //var ubo_device_memory : [instance.MAX_CONCURRENT_FRAMES]c.VkDeviceMemory = undefined;
    //var ubo_mmio : [instance.MAX_CONCURRENT_FRAMES]?*anyopaque = undefined;

    //for (0..instance.MAX_CONCURRENT_FRAMES) |i| {
    //    c.createBuffer();
    //}

    var frame_count: u64 = 0;
    var current_frame_index: u32 = 0;

    var previous_frame_time: f64 = 0.0;

    while (c.glfwWindowShouldClose(instance.window) == 0) {
        c.glfwPollEvents();

        const current_time = c.glfwGetTime();
        const frame_delta: f64 = current_time - previous_frame_time;
        previous_frame_time = current_time;

        std.debug.print("\tw: {:5} x: {d:.2} y: {d:.2} {d:.3}ms {}   \r", .{ w, xpos, ypos, (frame_delta * 100.0), frame_count });
        try instance.draw_frame(current_frame_index, instance.vertex_buffers, vertices.len);

        current_frame_index = (current_frame_index + 1) % instance.MAX_CONCURRENT_FRAMES;
        frame_count += 1;
    }

    _ = c.vkDeviceWaitIdle(instance.device);
    c.vkFreeMemory(instance.device, vertex_device_memory, null);
    for (instance.vertex_buffers) |buffer| {
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
