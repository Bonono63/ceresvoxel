//Proceeds to zig all over the place...
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");

const ENGINE_NAME = "CeresVoxel";

var xpos: f64 = 0.0;
var ypos: f64 = 0.0;
var w: bool = false;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    const allocator = arena.allocator();

    var instance = vulkan.Instance{};
    try instance.initialize_state(ENGINE_NAME, ENGINE_NAME, &allocator);

    _ = c.glfwSetKeyCallback(instance.window, key_callback);

    _ = c.glfwSetCursorPosCallback(instance.window, cursor_pos_callback);
    _ = c.glfwSetWindowUserPointer(instance.window, &instance);
    _ = c.glfwSetFramebufferSizeCallback(instance.window, window_resize_callback);

    var frame_count: u64 = 0;
    var current_frame_index: u32 = 0;

    var previous_frame_time: f64 = 0.0;

    while (c.glfwWindowShouldClose(instance.window) == 0) {
        c.glfwPollEvents();

        const current_time = c.glfwGetTime();
        const frame_delta: f64 = current_time - previous_frame_time;
        previous_frame_time = current_time;

        std.debug.print("\tw: {:5} x: {d:.2} y: {d:.2} {d:.3}ms {}   \r", .{ w, xpos, ypos, (frame_delta * 100.0), frame_count });
        try instance.draw_frame(current_frame_index);

        current_frame_index = (current_frame_index + 1) % instance.MAX_CONCURRENT_FRAMES;
        frame_count += 1;
    }

    _ = c.vkDeviceWaitIdle(instance.device);
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
