//!Main entry point for CeresVoxel
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");
const zm = @import("zmath");
const chunk = @import("chunk.zig");
const physics = @import("physics.zig");
const cm = @import("ceresmath.zig");

pub const InputState = packed struct {
    MOUSE_SENSITIVITY : f64 = 0.1,
    input_vec: zm.Vec = .{0.0,0.0,0.0,0.0},
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

pub const CameraState = struct {
    yaw: f32 = std.math.pi / 2.0,
    pitch: f32 = 0.0,
    free_cam: bool = false,
    // free cam only
    speed: f32 = 5.0,

    pub fn look(self: *const CameraState) zm.Quat {
        const result = cm.qnormalize(@Vector(4, f32){
            @cos(self.yaw / 2.0) * @cos(0.0),
            @sin(self.pitch / 2.0) * @cos(0.0),
            @sin(self.yaw / 2.0) * @cos(0.0),
            @sin(0.0),
        });

        return result;
    }
    
    pub fn lookV(self: *const CameraState) zm.Vec {
        const result = zm.normalize3(@Vector(4, f32){
            @cos(self.yaw) * @cos(self.pitch),
            @sin(self.pitch),
            @sin(self.yaw) * @cos(self.pitch),
            0.0,
        });

        return result;
    }

    pub fn up(self: *const CameraState) zm.Vec {
        _ = &self;
        return .{0.0,1.0,0.0,0.0};
    }

    pub fn right(self: *const CameraState) zm.Vec {
        return zm.normalize3(zm.cross3(self.up(), self.lookV()));
    }
};

const Type = enum {
    voxel_space,
    particle,
    player,
    other,
};

pub const Object = struct {
    ///This should be sufficient for space exploration at a solar system level
    position: @Vector(3, f128),
    ///There is phyicsally no reason to be able to go above a speed
    ///or acceleration of 2.4 billion meters a second
    velocity: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, // meters per second
    // TODO decide whether a f32 is sufficient precision for mass calculations
    inverse_mass: f32,
    ///Sum accelerations of the forces acting on the particle
    force_accumulation: zm.Vec = .{0.0, 0.0, 0.0, 0.0},
    ///Helps with simulation stability, but for space it doesn't make much sense
    linear_damping: f32 = 0.99999,

    gravity: bool = true,
    planet: bool = false,
    orbit_radius: f128 = 0.0,
    /// center of the object's orbit
    barocenter: @Vector(3, f128) = .{0.0,0.0,0.0},
    eccentricity: f32 = 1.0,
    eccliptic_offset: @Vector(2, f32) = .{0.0, 0.0},

    orientation: zm.Quat = zm.qidentity(),
    /// axis-angle representation
    angular_velocity: zm.Vec = .{0.0, 0.0, 0.0, 0.0},
    /// factor for reducing the angular velocity every tick
    angular_damping: f32 = 0.99999,
    inverse_inertia_tensor: zm.Mat = zm.inverse(zm.identity()),
    ///change in axis is based on direction,
    ///strength the the coefficient from if it was a unit vector
    torque_accumulation: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, 
    ///Collisions are only possible with boxes (other shapes can be added, but I can't be bothered)
    ///Make sure to only ever put in half the length of each dimension of the collision box
    half_size: zm.Vec,
   
    body_type: Type,
    particle_time: u32 = 0,
    
    // voxel space data
    size: @Vector(3, u32) = .{0,0,0},
    chunks: std.ArrayList(u8) = undefined, // 32768 * chunk count

    /// Returns the object's transform (for rendering or physics)
    /// for safety reasons should only be called on objects within f32's range.
    pub fn transform(self: *const Body) zm.Mat {
        const center: zm.Vec = cm.scale_f32(self.half_size, -1.0);
        const world_pos: zm.Mat = zm.translationV(.{
                @as(f32, @floatCast(self.position[0])),
                @as(f32, @floatCast(self.position[1])),
                @as(f32, @floatCast(self.position[2])),
                0.0,
            });
        var result: zm.Mat = zm.identity();
        result = zm.mul(zm.matFromQuat(self.orientation), zm.translationV(center));
        return zm.mul(result, world_pos);
    }

    /// Returns the object's transform (for rendering or physics)
    /// for safety reasons should only be called on objects within f32's range.
    pub fn render_transform(self: *const Body, player_pos: @Vector(3, f128)) zm.Mat {
        //const center: zm.Vec = cm.scale_f32(self.half_size, 1.0);
        const world_pos: zm.Mat = zm.translationV(.{
                @as(f32, @floatCast(self.position[0] - player_pos[0])),
                @as(f32, @floatCast(self.position[1] - player_pos[1])),
                @as(f32, @floatCast(self.position[2] - player_pos[2])),
                0.0,
            });
        return zm.mul(zm.matFromQuat(self.orientation), world_pos);
    }

    /// Returns the X axis given the body's current transform 
    pub fn getXAxis(self: *const Body) zm.Vec {
        return zm.mul(self.transform(), zm.Vec{1.0,0.0,0.0,0.0});
    }

    /// Returns the Y axis given the body's current transform 
    pub fn getYAxis(self: *const Body) zm.Vec {
        return zm.mul(self.transform(), zm.Vec{0.0,1.0,0.0,0.0});
    }
    
    /// Returns the Z axis given the body's current transform 
    pub fn getZAxis(self: *const Body) zm.Vec {
        return zm.mul(self.transform(), zm.Vec{0.0,0.0,1.0,0.0});
    }
};

///Stores arbitrary state of the game
pub const GameState = struct {
    objects: []Object,
    seed: u64 = 0,
    camera_state: CameraState,
    completion_signal: bool,
    allocator: *std.mem.Allocator,
};

pub const chicken = struct {
};

const ENGINE_NAME = "CeresVoxel";

var input_state = InputState{};

// Current mouse state (Must be global so it can be accessed by the mouse input callback)
var xpos: f64 = 0.0;
var ypos: f64 = 0.0;
var dx: f64 = 0.0;
var dy: f64 = 0.0;


pub fn main() !void {
    // ZIG INIT
    std.debug.print("[Info] Runtime Safety: {}\n", .{std.debug.runtime_safety});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //var fba = std.heap.FixedBufferAllocator(.{}){};
    defer {
        const heap_status = gpa.deinit();
        if (std.debug.runtime_safety)
            std.debug.print("[Info] Memory leaked during runtime: {}\n", .{heap_status});
    }

    //var fixed_allocator = fba.allocator();
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
        .PUSH_CONSTANT_SIZE = @sizeOf(zm.Mat) + @sizeOf(f32) + @sizeOf(u32), // view-proj matrix | aspect ratio | chunk index
        .chunk_render_style = .basic,
    };

    try vulkan.glfw_initialization();
    try vulkan_state.window_setup(vulkan_state.ENGINE_NAME, vulkan_state.ENGINE_NAME);
   
    // GLFW Callbacks
    _ = c.vulkan.glfwSetKeyCallback(vulkan_state.window, key_callback);

    _ = c.vulkan.glfwSetCursorPosCallback(vulkan_state.window, cursor_pos_callback);
    _ = c.vulkan.glfwSetWindowUserPointer(vulkan_state.window, @constCast(&vulkan_state));
    _ = c.vulkan.glfwSetFramebufferSizeCallback(vulkan_state.window, window_resize_callback);
    _ = c.vulkan.glfwSetMouseButtonCallback(vulkan_state.window, mouse_button_input_callback);

    // game and physics INIT

    var game_state = GameState{
        .completion_signal = true,
        .camera_state = CameraState{},
        .allocator = &allocator,
        .chunks = try allocator.alloc(u8, 32768 * 100), // can load at most 100 chunks at a time
        .chunk_vertex_indices = try allocator.alloc(u32, 100),
        .voxel_space_sizes = try allocator.alloc(@Vector(3, u32), 100), // can load at most 100 voxel spaces
    };
    defer allocator.free(game_state.chunks);
    defer allocator.free(game_state.voxel_space_sizes);
    
    _ = &game_state;
    
    var physics_state = physics.PhysicsState{
        .bodies = try std.ArrayList(physics.Body).initCapacity(allocator, 64),
        .sim_start_time = std.time.milliTimestamp(),
    };
    defer physics_state.bodies.deinit(allocator);
    
    // "Sun"
    try physics_state.bodies.append(
        allocator,
        .{
        .position = .{0.0, 0.0, 0.0},
        .inverse_mass = 0.0,
        .planet = false,
        .gravity = false,
        .torque_accumulation = .{std.math.pi, 0.0, 0.0, 0.0},
        .half_size = .{0.5, 0.5, 0.5, 0.0},
        .body_type = .voxel_space
    }
    );
    
    
    //for (2..9) |index| {
    //    const rand = std.crypto.random;
    //    
    //    try physics_state.bodies.append(
    //        allocator,
    //        .{
    //            .position = .{0.0, 0.0, 0.0},
    //            .inverse_mass = 0.0,
    //            .planet = true,
    //            .gravity = false,
    //            .orbit_radius = @as(f128, @floatFromInt(index * index * index * 3)),
    //            .eccentricity = 1.0,
    //            .eccliptic_offset = .{rand.float(f32) / 10.0, rand.float(f32) / 10.0},
    //            .half_size = .{0.5, 0.5, 0.5, 0.0},
    //            .body_type = .voxel_space,
    //        }
    //    );
    //}

    // player
    try physics_state.bodies.append(
        allocator,
        .{
            .position = .{0.0, 0.0, 0.0},
            .inverse_mass = (1.0/100.0),
            .half_size = .{0.5, 1.0, 0.5, 0.0},
            .body_type = .player,
        }
    );
    physics_state.player_index = @intCast(physics_state.bodies.items.len - 1);
    
    try vulkan.render_init(&vulkan_state);

    // Game Loop and additional prerequisites
    var vomit_cooldown_previous_time: i64 = std.time.milliTimestamp();
    const VOMIT_COOLDOWN: i64 = 20;

    var prev_tick_time: i64 = 0;
    var prev_time: i64 = 0;
    const MINIMUM_PHYSICS_TICK_TIME: i64 = 20;
    const MINIMUM_RENDER_TICK_TIME: i64 = 0;

    var contacts = try std.ArrayList(physics.Contact).initCapacity(allocator, 64);
    defer contacts.deinit(allocator);

    var frame_count: u64 = 0;
    var current_frame_index: u32 = 0;

    var window_height: i32 = 0;
    var window_width: i32 = 0;

    var frame_time_buffer_index: u32 = 0;
    const FTCB_SIZE: u32 = 128;
    var frame_time_cyclic_buffer: [FTCB_SIZE]f32 = undefined;
    @memset(&frame_time_cyclic_buffer, 0.0);

    // Time in milliseconds in between frames, 60 is 16.666, 0.0 is 
    var fps_limit: f32 = 0.0;//3.03030303;//8.333;
    _ = &fps_limit;

    std.debug.print("fps limit: {}\n", .{fps_limit});

    var current_render_targets = try std.ArrayList(vulkan.RenderInfo).initCapacity(allocator, 200);

    // The responsibility of the main thread is to handle input and manage
    // all the other threads
    // This will ensure the lowest input state for the various threads and have slightly
    // better seperation of responsiblities
    // Camera state (yaw, pitch, and freecam) are all handled here as well
    while (c.vulkan.glfwWindowShouldClose(vulkan_state.window) == 0) {
        const current_time: i64 = std.time.milliTimestamp();
        prev_time = current_time;
        const delta_time: i64 = current_time - prev_tick_time;
        const delta_time_float: f64 = @as(f64, @floatFromInt(delta_time)) / 1000.0;
        
        c.vulkan.glfwPollEvents();
        
        if (input_state.control) {
            game_state.camera_state.speed = 100.0;
        } else {
            game_state.camera_state.speed = 5.0;
        }

        if (@abs(input_state.mouse_dx) > 0.0 and input_state.mouse_capture) {
            game_state.camera_state.yaw -= @as(f32, 
                @floatCast(input_state.mouse_dx * std.math.pi
                    / 180.0 * input_state.MOUSE_SENSITIVITY)
                );
            input_state.mouse_dx = 0.0;
        }
        
        if (@abs(input_state.mouse_dy) > 0.0 and input_state.mouse_capture) {
            game_state.camera_state.pitch += @as(f32, @floatCast(input_state.mouse_dy * std.math.pi / 180.0 * input_state.MOUSE_SENSITIVITY));
            if (game_state.camera_state.pitch >= std.math.pi / 2.0 - std.math.pi / 256.0) {
                game_state.camera_state.pitch = std.math.pi / 2.0 - std.math.pi / 256.0;
            }
            if (game_state.camera_state.pitch < - std.math.pi / 2.0 + std.math.pi / 256.0) {
                game_state.camera_state.pitch =  - std.math.pi / 2.0 + std.math.pi / 256.0;
            }
            input_state.mouse_dy = 0.0;
        }
        
        const look = game_state.camera_state.lookV();
        const up = game_state.camera_state.up();
        const right = game_state.camera_state.right();

        var input_vec: zm.Vec = .{0.0, 0.0, 0.0, 0.0};

        if (input_state.space) {
            input_vec -= cm.scale_f32(
                up,
                game_state.camera_state.speed
                );
        }
        if (input_state.shift) {
            input_vec += cm.scale_f32(
                up,
                game_state.camera_state.speed
                );
        }
        if (input_state.w) {
            input_vec += cm.scale_f32(
                look,
                game_state.camera_state.speed
                );
        }
        if (input_state.s) {
            input_vec -= cm.scale_f32(
                look,
                game_state.camera_state.speed
                );
        }
        if (input_state.d) {
            input_vec += cm.scale_f32(
                right,
                game_state.camera_state.speed
                );
        }
        if (input_state.a) {
            input_vec -= cm.scale_f32(
                right,
                game_state.camera_state.speed
                );
        }
            
        // TODO make this only work while glfw is initialized it is producing that error
        if (input_state.mouse_capture)
        {
            c.vulkan.glfwSetInputMode(vulkan_state.window, c.vulkan.GLFW_CURSOR, c.vulkan.GLFW_CURSOR_DISABLED);
        }
        else
        {
            c.vulkan.glfwSetInputMode(vulkan_state.window, c.vulkan.GLFW_CURSOR, c.vulkan.GLFW_CURSOR_NORMAL);
        }
        
        if (@abs(current_time - prev_tick_time) > MINIMUM_RENDER_TICK_TIME) {
            const chunk_render_targets = generate_chunk_render_targets();
            current_render_targets.appendSliceAssumeCapacity(vulkan_state.render_targets);
            current_render_targets.appendSliceAssumeCapacity(chunk_render_targets);

            const render_frame: vulkan.RenderFrame = vulkan.RenderFrame{
                .render_targets = current_render_targets,
                .bodies = physics_state.bodies.items,
                .particle_count = physics_state.particle_count,
                .player_index = physics_state.player_index,
                .camera_state = &game_state.camera_state,
            };

            c.vulkan.glfwGetWindowSize(vulkan_state.window, &window_width, &window_height);
            const aspect_ratio : f32 = @as(f32, 
                @floatFromInt(window_width))
                / @as(f32, @floatFromInt(window_height)
                    );

            const player_pos: zm.Vec = .{
                0.0,//@floatCast(bodies[game_state.player_state.physics_index].position[0]),
                0.0,//@floatCast(bodies[game_state.player_state.physics_index].position[1] - 0.5),
                0.0,//@floatCast(bodies[game_state.player_state.physics_index].position[2]),
                0.0,
            };
            const view: zm.Mat = zm.lookToLh(player_pos, look, up);
            const projection: zm.Mat = zm.perspectiveFovLh(
                1.0,
                aspect_ratio,
                0.1,
                1000.0
                );
            const view_proj: zm.Mat = zm.mul(view, projection);
            
            
            @memcpy(
                vulkan_state.push_constant_data[0..64],
                @as([]u8, @ptrCast(@constCast(&view_proj)))[0..64]
                );
            @memcpy(
                vulkan_state.push_constant_data[@sizeOf(zm.Mat)..(@sizeOf(zm.Mat) + 4)],
                @as([*]u8, @ptrCast(@constCast(&aspect_ratio)))[0..4]
                );
            @memset(
                vulkan_state.push_constant_data[(@sizeOf(zm.Mat) + 4)..(@sizeOf(zm.Mat) + 4 + 4)],
                0
                );
            
            //const chunk_offsets: []@Vector(3, u32);

            try vulkan.update_chunk_ubo(
                &vulkan_state,
                render_frame.bodies,
                //chunk_offsets,
                render_frame.player_index, // This should probably have a place in the RenderFrame if we redo that
                1,
                );
            
            try vulkan.update_particle_ubo(
                &vulkan_state,
                render_frame.bodies,
                render_frame.player_index,
                0
                );

            vulkan_state.render_targets.items[1].instance_count = render_frame.particle_count;

            // DRAW
            try vulkan_state.draw_frame(current_frame_index, &vulkan_state.render_targets.items);
            
            var average_frame_time: f32 = 0;
            for (frame_time_cyclic_buffer) |time|
            {
                average_frame_time += time;
            }
            average_frame_time /= FTCB_SIZE;

            std.debug.print("{s} {} pos:{d:2.1} {d:2.1} {d:2.1} y:{d:3.1} p:{d:3.1} {d:.3}ms {d:5.1}fps    \r", .{
                if (input_state.mouse_capture) "on " else "off",
                physics_state.bodies.items.len,
                @as(f32, @floatCast(render_frame.bodies[render_frame.player_index].position[0])), 
                @as(f32, @floatCast(render_frame.bodies[render_frame.player_index].position[1])),
                @as(f32, @floatCast(render_frame.bodies[render_frame.player_index].position[2])),
                render_frame.camera_state.yaw,
                render_frame.camera_state.pitch,
                average_frame_time * 1000.0,
                1.0/average_frame_time,
            });
            
            frame_time_cyclic_buffer[frame_time_buffer_index] = @floatCast(delta_time_float);
            if (frame_time_buffer_index < FTCB_SIZE - 1) {
                frame_time_buffer_index += 1;
            } else {
                frame_time_buffer_index = 0;
            }

            current_frame_index = (current_frame_index + 1) % vulkan_state.MAX_CONCURRENT_FRAMES;
            frame_count += 1;
        }

        if (@abs(current_time - prev_tick_time) > MINIMUM_PHYSICS_TICK_TIME) {
            // PHYSICS AND LOGIC SECTION

            prev_tick_time = current_time;

            const player_physics_state: *physics.Body = &physics_state.bodies.items[physics_state.player_index];

            player_physics_state.*.velocity = input_vec;

            for (physics_state.bodies.items, 0..physics_state.bodies.items.len) |body, index| {
                if (body.body_type == .particle) {
                    const MAX_PARTICLE_TIME: u32 = 1000;
                    if (body.particle_time < MAX_PARTICLE_TIME) {
                        physics_state.bodies.items[index].particle_time += 1;
                    } else {
                        _ = physics_state.bodies.orderedRemove(index);
                        physics_state.particle_count -= 1;
                    }
                }
            }
            
            if (input_state.e and current_time - vomit_cooldown_previous_time > VOMIT_COOLDOWN) {
                try physics_state.bodies.append(
                    allocator,
                    .{
                        .position = player_physics_state.*.position,
                        .inverse_mass = 1.0 / 32.0,
                        .orientation = game_state.camera_state.look(),
                        .velocity = cm.scale_f32(
                            game_state.camera_state.lookV(), 1.0 * 32.0)
                            + player_physics_state.*.velocity,
                        //.angular_velocity = .{1.0,0.0,0.0,0.0},
                        .half_size = .{0.5, 0.5, 0.5, 0.0},
                        .body_type = .particle,
                    }
                );

                physics_state.particle_count += 1;
                
                vomit_cooldown_previous_time = current_time;
            }
           
            // TODO throw this into a different thread and join when the tick is done
            try physics.physics_tick(
                &allocator,
                delta_time_float,
                physics_state.sim_start_time,
                physics_state.bodies.items,
                &contacts
                );
        }

        current_render_targets.clearRetainingCapacity();

    }
   
    _ = c.vulkan.vkDeviceWaitIdle(vulkan_state.device);
    vulkan_state.cleanup();
}


pub export fn key_callback(window: ?*c.vulkan.GLFWwindow, key: i32, scancode: i32, action: i32, mods: i32) void {
    _ = &scancode;
    _ = &mods;

    switch (key) {
        c.vulkan.GLFW_KEY_ESCAPE => {
            c.vulkan.glfwSetWindowShouldClose(window, c.vulkan.GLFW_TRUE);
        },
        c.vulkan.GLFW_KEY_LEFT_CONTROL => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.control = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.control = false;
            }
        },
        c.vulkan.GLFW_KEY_SPACE => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.space = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.space = false;
            }
        },
        c.vulkan.GLFW_KEY_LEFT_SHIFT => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.shift = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.shift = false;
            }
        },
        c.vulkan.GLFW_KEY_W => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.w = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.w = false;
            }
        },
        c.vulkan.GLFW_KEY_A => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.a = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.a = false;
            }
        },
        c.vulkan.GLFW_KEY_S => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.s = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.s = false;
            }
        },
        c.vulkan.GLFW_KEY_D => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.d = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.d = false;
            }
        },
        c.vulkan.GLFW_KEY_E => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.e = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.e = false;
            }
        },
        c.vulkan.GLFW_KEY_T => {
            if (action == c.vulkan.GLFW_RELEASE) {
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

pub export fn cursor_pos_callback(window: ?*c.vulkan.GLFWwindow, _xpos: f64, _ypos: f64)  void {
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

pub export fn mouse_button_input_callback(window: ?*c.vulkan.GLFWwindow, button: i32, action: i32, mods: i32) void {
    _ = &button;
    _ = &window;
    _ = &mods;
    _ = &action;

    switch (button) {
        c.vulkan.GLFW_MOUSE_BUTTON_LEFT => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.left_click = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.left_click = false;
            }
        },
        c.vulkan.GLFW_MOUSE_BUTTON_RIGHT => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.right_click = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.right_click = false;
            }
        },
        else => {},
    }
}

pub export fn window_resize_callback(window: ?*c.vulkan.GLFWwindow, width: c_int, height: c_int) void {
    _ = &width;
    _ = &height;
    const instance: *vulkan.VulkanState = @ptrCast(@alignCast(c.vulkan.glfwGetWindowUserPointer(window)));
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

pub fn generate_chunk_render_targets(
    allocator: *std.mem.Allocator,
    bodies: []physics.Body,
    vertex_data: []
    ) ![]vulkan.RenderInfo {
    var list = try std.ArrayList(vulkan.RenderInfo).initCapacity(allocator.*, 10);
    defer list.deinit();

    var i: u32 = 0;
    for (bodies) |body| {
        if (body.body_type = .voxel_space) {
            list.append(
                allocator.*,
                vulkan.RenderInfo{
                    .vertex_index = i,
                    .pipeline_index = 2,
                    .vertex_count = ,
                }
                );
            i += 1;
        }
    }

    var slice = try list.toOwnedSlice; // This saves another allocation and free
}
