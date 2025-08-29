//Proceeds to zig all over the place...
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");
const zm = @import("zmath");
const chunk = @import("chunk.zig");
const physics = @import("physics.zig");
const cm = @import("ceresmath.zig");

pub const InputState = packed struct {
    MOUSE_SENSITIVITY : f64 = 0.1,
    w : bool = false,
    a : bool = false,
    s : bool = false,
    d : bool = false,
    e : bool = false,
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
    // TODO switch to quat for camera dir
    yaw: f32 = std.math.pi/2.0,
    pitch: f32 = 0.0,
    up: zm.Vec = .{ 0.0, -1.0, 0.0, 0.0},
    // Unit vector of player input
    input_vec: zm.Vec = .{0.0, 0.0, 0.0, 0.0},
    //camera_rot: zm.Quat,
    speed: f32 = 5.0,
    physics_index: u32,

    pub fn look(self: *PlayerState) !zm.Quat {
        const result = zm.normalize3(@Vector(4, f32){
            @as(f32, @floatCast(std.math.cos(self.yaw) * std.math.cos(self.pitch))),
            @as(f32, @floatCast(std.math.sin(self.pitch))),
            @as(f32, @floatCast(std.math.sin(self.yaw) * std.math.cos(self.pitch))),
            0.0,
        });

        return result;
    }
    
    pub fn lookV(self: *PlayerState) !zm.Vec {
        const result = zm.normalize3(@Vector(4, f32){
            @as(f32, @floatCast(std.math.cos(self.yaw) * std.math.cos(self.pitch))),
            @as(f32, @floatCast(std.math.sin(self.pitch))),
            @as(f32, @floatCast(std.math.sin(self.yaw) * std.math.cos(self.pitch))),
            0.0,
        });

        return result;
    }
};

pub const GameObject = struct {

    //PHYSICS

    // This should be sufficient for space exploration at a solar system level
    position: @Vector(3, f128),
    // There is phyicsally no reason to be able to go above a speed or acceleration of 2.4 billion meters a second
    velocity: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, // meters per second
    // TODO decide whether a f32 is sufficient precision for mass calculations
    inverse_mass: f32,
    // Sum accelerations of the forces acting on the particle
    force_accumulation: zm.Vec = .{0.0, 0.0, 0.0, 0.0},
    // Helps with simulation stability, but for space it doesn't make much sense
    linear_damping: f32 = 0.99999,

    gravity: bool = true,
    planet: bool = false,
    orbit_radius: f128 = 0.0,
    barocenter: @Vector(3, f128) = .{0.0,0.0,0.0}, // center of the object's orbit
    eccentricity: f32 = 1.0,
    eccliptic_offset: @Vector(2, f32) = .{0.0, 0.0},

    orientation: zm.Quat = zm.qidentity(),
    angular_velocity: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, // axis-angle representation
    angular_damping: f32 = 0.99999,
    inverse_inertia_tensor: zm.Mat = zm.inverse(zm.identity()),
    torque_accumulation: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, //change in axis is based on direction, strength the the coefficient from if it was a unit vector
};

const PARTICLE_MAX_TIME: u32 = 1000;

pub const ParticleHandle = struct {
    time: u32 = 0,
    physics_index: u32 = undefined,
};

pub const GameState = struct {
    voxel_spaces: std.ArrayList(chunk.VoxelSpace),
    particles: std.ArrayList(ParticleHandle),
    seed: u64 = 0,
    player_state: PlayerState,
    completion_signal: bool,
    allocator: *std.mem.Allocator,
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

    _ = &arena;
    var allocator = gpa.allocator();//arena.allocator();

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

    var game_state = GameState{
        .voxel_spaces = std.ArrayList(chunk.VoxelSpace).init(allocator),
        .particles = std.ArrayList(ParticleHandle).init(allocator),
        .player_state = undefined,
        .completion_signal = true,
        .allocator = &allocator,
    };
    defer game_state.voxel_spaces.deinit();
    defer game_state.particles.deinit();
    
    var physics_state = physics.PhysicsState{
        .bodies = std.ArrayList(physics.Body).init(allocator),
        .broad_contact_list = std.ArrayList([2]*physics.Body).init(allocator),
        .sim_start_time = std.time.milliTimestamp(),
    };
    defer physics_state.bodies.deinit();
    defer physics_state.broad_contact_list.deinit();

    try physics_state.broad_contact_list.ensureUnusedCapacity(100);
    
    // "Sun"
    try physics_state.bodies.append(.{
        .position = .{0.0, 0.0, 0.0},
        .inverse_mass = 0.0,
        .planet = false,
        .gravity = false,
        .torque_accumulation = .{std.math.pi, 0.0, 0.0, 0.0},
    });
    
    try game_state.voxel_spaces.append(.{
        .size = .{1,1,1},
        .physics_index = @intCast(physics_state.bodies.items.len - 1),
    });
    physics_state.sun_index = @intCast(physics_state.bodies.items.len - 1);
    
    for (2..9) |index| {
        const rand = std.crypto.random;
        try physics_state.bodies.append(.{
            .position = .{0.0, 0.0, 0.0},
            .inverse_mass = 0.0,
            .planet = true,
            .gravity = false,
            .orbit_radius = @as(f128, @floatFromInt(index * index * index * 3)),
            .eccentricity = 1.0,
            .eccliptic_offset = .{rand.float(f32) / 10.0, rand.float(f32) / 10.0},
        });
        
        try game_state.voxel_spaces.append(.{
            .size = .{1,1,1},
            .physics_index = @intCast(physics_state.bodies.items.len - 1),
        });
    }

    // player
    try physics_state.bodies.append(.{
        .position = .{0.0, 100, 0.0},
        .inverse_mass = (1.0/100.0),
    });
    game_state.player_state = PlayerState{.physics_index = @intCast(physics_state.bodies.items.len - 1)};

    var render_done: bool = false;
    var render_ready: bool = false;
    var render_thread = try std.Thread.spawn(.{}, vulkan.render_thread, .{&vulkan_state, &game_state, &input_state, &physics_state, &render_ready, &render_done});
    defer render_thread.join();

    physics_state.display_bodies[0] = try game_state.allocator.alloc(physics.Body, 0);
    physics_state.display_bodies[1] = try game_state.allocator.alloc(physics.Body, 0);
    defer game_state.allocator.free(physics_state.display_bodies[0]);
    defer game_state.allocator.free(physics_state.display_bodies[1]);

    var vomit_cooldown_previous_time: i64 = std.time.milliTimestamp();

    var prev_tick_time: i64 = 0;
    var prev_time: i64 = 0;
    const MINIMUM_TICK_TIME: i64 = 40;
    
    physics_state.display_bodies[physics_state.display_index] = try game_state.allocator.realloc(physics_state.display_bodies[physics_state.display_index], physics_state.bodies.items.len);
    @memcpy(physics_state.display_bodies[physics_state.display_index], physics_state.bodies.items);

    while (!render_ready) {
        std.time.sleep(1);
    }

    std.debug.print("[Debug] render ready\n", .{});

    while (!render_done) {
        const current_time: i64 = std.time.milliTimestamp();
        prev_time = current_time;
        const delta_time: i64 = current_time - prev_tick_time;
        const delta_time_float: f64 = @as(f64, @floatFromInt(delta_time)) / 1000.0;

        if (input_state.control) {
            game_state.player_state.speed = 30.0;
        } else {
            game_state.player_state.speed = 5.0;
        }
        
        const look = try game_state.player_state.lookV();

        const right = zm.normalize3(zm.cross3(look, game_state.player_state.up));

        game_state.player_state.input_vec = .{0.0, 0.0, 0.0, 0.0};

        if (input_state.space) {
            game_state.player_state.input_vec -= cm.scale_f32(game_state.player_state.up, game_state.player_state.speed);
        }
        if (input_state.shift) {
            game_state.player_state.input_vec += cm.scale_f32(game_state.player_state.up, game_state.player_state.speed);
        }
        if (input_state.w) {
            game_state.player_state.input_vec += cm.scale_f32(look, game_state.player_state.speed);
        }
        if (input_state.s) {
            game_state.player_state.input_vec -= cm.scale_f32(look, game_state.player_state.speed);
        }
        if (input_state.d) {
            game_state.player_state.input_vec -= cm.scale_f32(right, game_state.player_state.speed);
        }
        if (input_state.a) {
            game_state.player_state.input_vec += cm.scale_f32(right, game_state.player_state.speed);
        }

        if (@abs(current_time - prev_tick_time) > MINIMUM_TICK_TIME) {
            prev_tick_time = current_time;

            physics_state.bodies.items[game_state.player_state.physics_index].velocity = game_state.player_state.input_vec;
            
            physics.physics_tick(delta_time_float, physics_state.bodies.items, &physics_state);
            
            if (input_state.e and current_time - vomit_cooldown_previous_time > 20) {
                const player_pos = physics_state.bodies.items[game_state.player_state.physics_index].position;
                const pos = .{player_pos[0] - 0.5, player_pos[1] - 0.5, player_pos[2] - 0.5};
                try physics_state.bodies.append(.{
                        .position = pos,
                        .inverse_mass = 1.0 / 32.0,
                        .orientation = physics_state.bodies.items[game_state.player_state.physics_index].orientation,
                        .velocity = cm.scale_f32(try game_state.player_state.look(), 50.0),
                });

                try game_state.particles.append(.{.physics_index = @as(u32, @intCast(physics_state.bodies.items.len - 2))});
                
                vomit_cooldown_previous_time = current_time;
            }
            
            if (game_state.particles.items.len > 0) {
                vulkan_state.render_targets.items[1].instance_count = @as(u32, @intCast(game_state.particles.items.len - 1));
            }
        }
        
        const next_display_index = (physics_state.display_index + 1) % 2;
        physics_state.display_bodies[next_display_index] = try game_state.allocator.realloc(physics_state.display_bodies[next_display_index], physics_state.bodies.items.len);
        @memcpy(physics_state.display_bodies[next_display_index], physics_state.bodies.items);
        physics_state.display_index = next_display_index;
        
        if (render_done) {
            game_state.completion_signal = false;
        }
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
        c.GLFW_KEY_E => {
            if (action == c.GLFW_PRESS) {
                input_state.e = true;
            }
            if (action == c.GLFW_RELEASE) {
                input_state.e = false;
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

    if (input_state.mouse_capture) {
        input_state.mouse_dx += dx;
        input_state.mouse_dy += dy;
    }
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
