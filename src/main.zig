//Proceeds to zig all over the place...
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");
const zm = @import("zmath");
const chunk = @import("chunk.zig");
const physics = @import("physics.zig");

pub const InputState = packed struct {
    MOUSE_SENSITIVITY : f64 = 0.1,
    w : bool = false,
    a : bool = false,
    s : bool = false,
    d : bool = false,
    space : bool = false,
    shift : bool = false,
    control : bool = false,
    mouse_capture : bool = true,
    left_click: bool = false,
    right_click: bool = false,
    mouse_dx: f64 = 0.0,
    mouse_dy: f64 = 0.0,
};

const PlayerState = struct {
    pos: @Vector(3, f64) = .{ 0.0, 0.0, -1.0 },
    yaw: f32 = std.math.pi/2.0,
    pitch: f32 = 0.0,
    up: zm.Vec = .{ 0.0, -1.0, 0.0, 1.0},
    //camera_rot: zm.Quat,
    speed: u32 = 5,
};

pub const GameState = struct {
    voxel_spaces: []chunk.VoxelSpace = undefined,
    seed: u64 = 0,
    player_state: PlayerState,
    completion_signal: bool,
};


var input_state = InputState{};

const ENGINE_NAME = "CeresVoxel";

var xpos: f64 = 0.0;
var ypos: f64 = 0.0;
var dx: f64 = 0.0;
var dy: f64 = 0.0;


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
    var vulkan_state = vulkan.VulkanState{
        .ENGINE_NAME = ENGINE_NAME,
        .allocator = &allocator,
        .MAX_CONCURRENT_FRAMES = 2, // basically double buffering
        .PUSH_CONSTANT_SIZE = @sizeOf(zm.Mat) + @sizeOf(f32),
    };

    try vulkan.glfw_initialization();
    try vulkan_state.window_setup(vulkan_state.ENGINE_NAME, vulkan_state.ENGINE_NAME);
    
    _ = c.glfwSetKeyCallback(vulkan_state.window, key_callback);

    _ = c.glfwSetCursorPosCallback(vulkan_state.window, cursor_pos_callback);
    _ = c.glfwSetWindowUserPointer(vulkan_state.window, @constCast(&vulkan_state));
    _ = c.glfwSetFramebufferSizeCallback(vulkan_state.window, window_resize_callback);
    _ = c.glfwSetMouseButtonCallback(vulkan_state.window, mouse_button_input_callback);

    // TODO move input and character movement into physics thread 
    //var speed : f32 = 5;
    //if (input_state.control)
    //{
    //    speed = 100;
    //}
    //
    //if (input_state.space)
    //{
    //    player_state.pos -= .{ up[0] * frame_delta * speed, up[1] * frame_delta * speed, up[2] * frame_delta * speed };
    //}
    //if (input_state.shift)
    //{
    //    player_state.pos += .{ up[0] * frame_delta * speed, up[1] * frame_delta * speed, up[2] * frame_delta * speed };
    //}
    //if (input_state.a)
    //{
    //    player_state.pos += .{ right[0] * frame_delta * speed, right[1] * frame_delta * speed, right[2] * frame_delta * speed };
    //}
    //if (input_state.d)
    //{
    //    player_state.pos -= .{ right[0] * frame_delta * speed, right[1] * frame_delta * speed, right[2] * frame_delta * speed };
    //}
    //if (input_state.w)
    //{
    //    player_state.pos -= .{ forward[0] * frame_delta * speed, forward[1] * frame_delta * speed, forward[2] * frame_delta * speed };
    //}
    //if (input_state.s)
    //{
    //    player_state.pos += .{ forward[0] * frame_delta * speed, forward[1] * frame_delta * speed, forward[2] * frame_delta * speed };
    //}
    
    var game_state = GameState{
        .voxel_spaces = try allocator.alloc(chunk.VoxelSpace, 2),
        .player_state = PlayerState{},
        .completion_signal = true,
    };
    defer allocator.free(game_state.voxel_spaces);

    for (0..game_state.voxel_spaces.len) |index| {
        game_state.voxel_spaces[index].size = .{1,1,1};
        game_state.voxel_spaces[index].pos = .{@as(f32, @floatFromInt(index * 2 + index)), 0.0, 0.0};
    }

    var physics_state = physics.PhysicsState{
        .particles = std.ArrayList(physics.Particle).init(allocator)
    };

    var render_done: bool = false;
    var render_thread = try std.Thread.spawn(.{}, vulkan.render_thread, .{&vulkan_state, &game_state, &input_state, &render_done});
    defer render_thread.join();
    _ = &render_thread;

    var physics_done: bool = false;
    var physics_thread = try std.Thread.spawn(.{}, physics.physics_thread, .{&physics_state, &input_state, &game_state.completion_signal, &physics_done});
    defer physics_thread.join();
    _ = &physics_thread;

    // not sure this is the best way to keep the main thread alive *shrug*
    while (!render_done or !physics_done) {
        if (render_done) {
            game_state.completion_signal = false;
        }
        std.time.sleep(1);
    }
}

pub fn key_callback(window: ?*c.GLFWwindow, key: i32, scancode: i32, action: i32, mods: i32) callconv(.C) void {
    _ = &scancode;
    _ = &mods;

    switch (key) {
        c.GLFW_KEY_ESCAPE => {
            c.glfwSetWindowShouldClose(window, c.GLFW_TRUE);
        },
        c.GLFW_KEY_LEFT_CONTROL => {
            if (action == c.GLFW_PRESS) {
                input_state.control = true;
            }
            if (action == c.GLFW_RELEASE) {
                input_state.control = false;
            }
        },
        c.GLFW_KEY_SPACE => {
            if (action == c.GLFW_PRESS) {
                input_state.space = true;
            }
            if (action == c.GLFW_RELEASE) {
                input_state.space = false;
            }
        },
        c.GLFW_KEY_LEFT_SHIFT => {
            if (action == c.GLFW_PRESS) {
                input_state.shift = true;
            }
            if (action == c.GLFW_RELEASE) {
                input_state.shift = false;
            }
        },
        c.GLFW_KEY_W => {
            if (action == c.GLFW_PRESS) {
                input_state.w = true;
            }
            if (action == c.GLFW_RELEASE) {
                input_state.w = false;
            }
        },
        c.GLFW_KEY_A => {
            if (action == c.GLFW_PRESS) {
                input_state.a = true;
            }
            if (action == c.GLFW_RELEASE) {
                input_state.a = false;
            }
        },
        c.GLFW_KEY_S => {
            if (action == c.GLFW_PRESS) {
                input_state.s = true;
            }
            if (action == c.GLFW_RELEASE) {
                input_state.s = false;
            }
        },
        c.GLFW_KEY_D => {
            if (action == c.GLFW_PRESS) {
                input_state.d = true;
            }
            if (action == c.GLFW_RELEASE) {
                input_state.d = false;
            }
        },
        c.GLFW_KEY_T => {
            if (action == c.GLFW_RELEASE) {
                if (input_state.mouse_capture == true)
                {
                    input_state.mouse_capture = false;
                }
                else
                {
                    input_state.mouse_capture = true;
                }
            }
        },
        else => {},
    }
}

pub fn cursor_pos_callback(window: ?*c.GLFWwindow, _xpos: f64, _ypos: f64) callconv(.C) void {
    _ = &window;
    dx = _xpos - xpos;
    dy = _ypos - ypos;

    xpos = _xpos;
    ypos = _ypos;

    input_state.mouse_dx += dx;
    input_state.mouse_dy += dy;
}

pub fn mouse_button_input_callback(window: ?*c.GLFWwindow, button: i32, action: i32, mods: i32) callconv(.C) void {
    _ = &button;
    _ = &window;
    _ = &mods;
    _ = &action;

    switch (button) {
        c.GLFW_MOUSE_BUTTON_LEFT => {
            if (action == c.GLFW_PRESS) {
                input_state.left_click = true;
            }
            if (action == c.GLFW_RELEASE) {
                input_state.left_click = false;
            }
        },
        c.GLFW_MOUSE_BUTTON_RIGHT => {
            if (action == c.GLFW_PRESS) {
                input_state.right_click = true;
            }
            if (action == c.GLFW_RELEASE) {
                input_state.right_click = false;
            }
        },
        else => {},
    }
}

pub fn window_resize_callback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    _ = &width;
    _ = &height;
    const instance: *vulkan.VulkanState = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));
    instance.framebuffer_resized = true;
}

// TODO redo this after we implement physics and stuffsies
//// TODO eventually shift to OBB instead of AABB test, but rotations aren't implemented so we can ignore that for now
///// origin must be a vector from the corner of the chunk to the player's position
//fn camera_block_intersection(chunk_data: *const [32768]u8, look: zm.Vec, camera_origin: @Vector(3, f32), chunk_origin: @Vector(3, f32), intersection: *@Vector(3,i32)) bool
//{
//    const max_distance: f32 = 100.0;
//    var result: bool = false;
//
//    var current_ray: @Vector(3, f32) = .{camera_origin[0], camera_origin[1], camera_origin[2]};
//    var current_pos: @Vector(3, i32) = undefined;
//    var current_distance: f32 = 0.0;
//    while (!result and current_distance < max_distance)
//    {
//        const step_vec: @Vector(3, f32) = .{look[0] * 0.15, look[1] * 0.15, look[2] * 0.15};
//        current_ray += step_vec;
//        current_distance += 0.15;
//        
//        current_pos[0] = @as(i32, @intFromFloat(@floor(current_ray[0])));
//        current_pos[1] = @as(i32, @intFromFloat(@floor(current_ray[1])));
//        current_pos[2] = @as(i32, @intFromFloat(@floor(current_ray[2])));
//        if (current_pos[0] >= chunk_origin[0] and current_pos[0] <= chunk_origin[0] + 31 and current_pos[1] >= chunk_origin[1] and current_pos[1] <= chunk_origin[1] + 31 and current_pos[2] >= chunk_origin[2] and current_pos[2] <= chunk_origin[2] + 31) {
//            const index: u32 = @abs(current_pos[0] - chunk_origin[0]) + @abs(current_pos[1] - chunk_origin[1]) * 32 + @abs(current_pos[2] - chunk_origin[2]) * 32 * 32;
//            if (chunk_data.*[index] != 0) {
//                result = true;
//                intersection.* = current_pos;
//            }
//        }
//    }
//    
//    return result;
//}

//TODO refactor this for f128 from physics/game state
pub fn distance_test(player_pos: *const @Vector(3, f64), space_pos: * const @Vector(3, f64), distance: f32) bool {
    var result = false;

    const distance_vec: zm.Vec = .{@floatCast(player_pos.*[0] - space_pos.*[0]), @floatCast(player_pos.*[1] - space_pos.*[1]), @floatCast(player_pos.*[2] - space_pos.*[2]), 0.0};
    const length = zm.length3(distance_vec);
    //std.debug.print("{}\n", .{length});

    if (length[0] < distance) {
        result = true;
    }

    return result;
}
