//Proceeds to zig all over the place...
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");

const ENGINE_NAME = "CeresVoxel";

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    const allocator = arena.allocator();

    var instance = vulkan.Instance{};
    try instance.initialize_state(ENGINE_NAME, ENGINE_NAME, &allocator);

    _ = c.glfwSetKeyCallback(instance.window, key_callback);

    _ = c.glfwSetCursorPosCallback(instance.window, cursor_pos_callback);

    while (c.glfwWindowShouldClose(instance.window) == 0) {
        c.glfwPollEvents();

        try instance.draw_frame();
    }

    _ = c.vkDeviceWaitIdle(instance.device);
    instance.cleanup(&allocator);
}

pub fn key_callback(window: ?*c.GLFWwindow, key: i32, scancode: i32, action: i32, mods: i32) callconv(.C) void {
    _ = &scancode;
    _ = &action;
    _ = &mods;

    switch (key) {
        c.GLFW_KEY_ESCAPE => {
            c.glfwSetWindowShouldClose(window, c.GLFW_TRUE);
        },
        else => {},
    }
}

pub fn cursor_pos_callback(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(.C) void {
    _ = &window;
    std.debug.print("\t x: {d:.2} y: {d:.2}\r", .{ xpos, ypos });
}
