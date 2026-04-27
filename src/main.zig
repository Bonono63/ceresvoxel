//!Main entry point for CeresVoxel
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");
const zm = @import("zmath");
const chunk = @import("chunk.zig");
const physics = @import("physics.zig");
const cm = @import("ceresmath.zig");
const mesh_generation = @import("mesh_generation.zig");

pub const InputState = packed struct {
    MOUSE_SENSITIVITY: f64 = 0.1,
    input_vec: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 },
    w: bool = false,
    a: bool = false,
    s: bool = false,
    d: bool = false,
    e: bool = false,
    space: bool = false,
    shift: bool = false,
    control: bool = false,
    mouse_capture: bool = true,
    p: bool = false, // edit mode
    equal: bool = false, // cycle print modes
    minus: bool = false, // cycle object select
    tab: bool = false, // cycle edit index
    i: bool = false, // property increment
    o: bool = false, // property decrement
    g: bool = false,
    one: bool = false,
    two: bool = false,
    three: bool = false,
    four: bool = false,
    five: bool = false,
    left_click: bool = false,
    right_click: bool = false,
    mouse_dx: f64 = 0.0,
    mouse_dy: f64 = 0.0,
    scroll_dy: f64 = 0.0,
};

pub const ClientState = struct {
    yaw: f32 = std.math.pi / 2.0,
    pitch: f32 = 0.0,
    /// Whether the camera position is constrained to the player's head or not
    free_cam: bool = false,
    free_cam_speed: f32 = 15.0,
    camera_pos: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 },
    /// For use once OBB system is finished
    camera_direction: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 },
    selected_object: i32 = -1, // -1 represents none selected

    pub fn look(self: *const ClientState) zm.Quat {
        const result = cm.qnormalize(@Vector(4, f32){
            @cos(self.yaw / 2.0) * @cos(0.0),
            @sin(self.pitch / 2.0) * @cos(0.0),
            @sin(self.yaw / 2.0) * @cos(0.0),
            @sin(0.0),
        });

        return result;
    }

    pub fn lookV(self: *const ClientState) zm.Vec {
        const result = zm.normalize3(@Vector(4, f32){
            @cos(self.yaw) * @cos(self.pitch),
            @sin(self.pitch),
            @sin(self.yaw) * @cos(self.pitch),
            0.0,
        });

        return result;
    }

    pub fn up(self: *const ClientState) zm.Vec {
        _ = &self;
        return .{ 0.0, 1.0, 0.0, 0.0 };
    }

    pub fn right(self: *const ClientState) zm.Vec {
        return zm.normalize3(zm.cross3(self.up(), self.lookV()));
    }
};

pub const Type = enum {
    voxel_space,
    particle,
    player,
    line,
    other,
};

pub const CollisionType = enum {
    NONE,
    COLLISION,
    PLAYER_SELECT,
};

pub const Object = struct {
    ///This should be sufficient for space exploration at a solar system level
    position: @Vector(3, f128),
    ///There is phyicsally no reason to be able to go above a speed
    ///or acceleration of 2.4 billion meters a second
    velocity: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 }, // meters per second
    acceleration: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 },
    // TODO decide whether a f32 is sufficient precision for mass calculations
    inverse_mass: f32,
    ///Sum accelerations of the forces acting on the particle
    force_accumulation: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 },
    ///Helps with simulation stability, but for space it doesn't make much sense
    linear_damping: f32 = 0.99999,
    orientation: zm.Quat = zm.qidentity(),
    /// quat representation
    angular_velocity: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 },
    /// factor for reducing the angular velocity every tick
    angular_damping: f32 = 0.99999,
    inverse_inertia_tensor: zm.Mat = zm.inverse(zm.identity()),
    ///change in axis is based on direction,
    ///strength the the coefficient from if it was a unit vector
    torque_accumulation: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 },
    ///Collisions are only possible with boxes (other shapes can be added, but I can't be bothered)
    ///Make sure to only ever put in half the length of each dimension of the collision box
    half_size: zm.Vec,
    last_frame_acceleration: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 },

    colliding: CollisionType = CollisionType.NONE,

    body_type: Type,
    particle_time: u32 = 0,

    // TODO implement proper material indexing
    restitution: f32 = 0.2,
    lock_pos: bool = false,
    lock_rot: bool = false,

    gravity: bool = true,
    planet: bool = false,
    orbit_radius: f128 = 0.0,
    barycenter: @Vector(2, f128) = .{ 0.0, 0.0 },
    eccliptic_offset: @Vector(2, f32) = .{ 0.0, 0.0 },

    // voxel space data
    size: @Vector(3, u32) = .{ 0, 0, 0 },
    chunks: std.ArrayList(chunk.Chunk) = undefined, // 32768 * chunk count
    chunk_occupancy: std.ArrayList(u32) = undefined,

    // TODO add a planet function init
    pub fn init(
        self: *const Object,
        _position: @Vector(3, f128),
        _velocity: zm.Vec,
        _inverse_mass: f32,
        _orientation: zm.Vec,
        _angular_velocity: zm.Vec,
        _half_size: zm.vec,
        _body_type: Type,
    ) void {
        self.position = _position;
        self.velocity = _velocity;
        self.inverse_mass = _inverse_mass;
        self.orientation = _orientation;
        self.angular_velocity = _angular_velocity;
        self.half_size = _half_size;
        self.body_type = _body_type;

        self.inverse_inertia_tensor = cm.calculate_cuboid_inertia_tensor(self.inverse_mass, self.half_size);
    }

    /// Returns the object's transform (for rendering or physics)
    /// for safety reasons should only be called on objects within f32's range.
    pub fn transform(self: *const Object) zm.Mat {
        var result: zm.Mat = zm.identity();
        const half_offset = zm.translationV(cm.scale_f32(self.half_size, -1.0));
        const world_pos = zm.translationV(.{
            @as(f32, @floatCast(self.position[0])),
            @as(f32, @floatCast(self.position[1])),
            @as(f32, @floatCast(self.position[2])),
            0.0,
        });
        result = zm.mul(result, half_offset);
        result = zm.mul(result, zm.matFromQuat(self.orientation));
        result = zm.mul(result, world_pos);
        return result;
    }

    /// Returns the object's transform (for rendering or physics)
    pub fn render_transform(self: *const Object, player_pos: @Vector(3, f128)) zm.Mat {
        var result: zm.Mat = zm.identity();
        const half_offset = zm.translationV(cm.scale_f32(self.half_size, -1.0));
        const world_pos = zm.translationV(.{
            @as(f32, @floatCast(self.position[0] - player_pos[0])),
            @as(f32, @floatCast(self.position[1] - player_pos[1])),
            @as(f32, @floatCast(self.position[2] - player_pos[2])),
            0.0,
        });
        const scale = zm.matFromArr(.{
            self.half_size[0], 0.0, 0.0, 0.0, //
            0.0, self.half_size[1], 0.0, 0.0, //
            0.0, 0.0, self.half_size[2], 0.0, //
            0.0, 0.0, 0.0, 0.5, //
        });
        result = zm.mul(result, scale);
        result = zm.mul(result, half_offset);
        result = zm.mul(result, zm.matFromQuat(self.orientation));
        result = zm.mul(result, world_pos);
        return result;
    }

    /// Returns the object's transform (for rendering or physics)
    /// for safety reasons should only be called on objects within f32's range.
    pub fn render_transform_chunk(self: *const Object, player_pos: @Vector(3, f128), chunk_index: u32) zm.Mat {
        var result: zm.Mat = zm.identity();
        const half_offset: zm.Mat = zm.translationV(.{
            -self.half_size[0],
            -self.half_size[1],
            -self.half_size[2],
            0.0,
        });
        const chunk_offset: zm.Mat = zm.translationV(.{
            @as(f32, @floatFromInt(chunk_index % self.size[0] * 32)),
            @as(f32, @floatFromInt(chunk_index / self.size[0] % self.size[1] * 32)),
            @as(f32, @floatFromInt(chunk_index / self.size[0] / self.size[1] % self.size[2] * 32)),
            0.0,
        });
        const world_pos: zm.Mat = zm.translationV(.{
            @as(f32, @floatCast(self.position[0] - player_pos[0])),
            @as(f32, @floatCast(self.position[1] - player_pos[1])),
            @as(f32, @floatCast(self.position[2] - player_pos[2])),
            0.0,
        });
        result = zm.mul(result, half_offset);
        result = zm.mul(result, chunk_offset);
        result = zm.mul(result, zm.matFromQuat(self.orientation));
        result = zm.mul(result, world_pos);
        return result;
    }

    /// Returns the X axis given the body's current transform
    pub fn getXAxis(self: *const Object) zm.Vec {
        const transform_matrix = self.transform();
        return .{
            transform_matrix[0][0], transform_matrix[0][1], transform_matrix[0][2], 0.0,
        };
    }

    /// Returns the Y axis given the body's current transform
    pub fn getYAxis(self: *const Object) zm.Vec {
        const transform_matrix = self.transform();
        return .{
            transform_matrix[1][0], transform_matrix[1][1], transform_matrix[1][2], 0.0,
        };
    }

    /// Returns the Z axis given the body's current transform
    pub fn getZAxis(self: *const Object) zm.Vec {
        const transform_matrix = self.transform();
        return .{
            transform_matrix[2][0], transform_matrix[2][1], transform_matrix[2][2], 0.0,
        };
    }

    pub fn getAxis(self: *const Object, index: u32) zm.Vec {
        switch (index % 3) {
            0 => {
                return self.getXAxis();
            },
            1 => {
                return self.getYAxis();
            },
            2 => {
                return self.getZAxis();
            },
            else => {
                std.debug.print("[Error] Invalid axis requested\n", .{});
                return .{ 0.0, 0.0, 0.0, 0.0 };
            },
        }
    }
};

///Stores arbitrary state of the game
pub const GameState = struct {
    objects: std.ArrayList(Object),
    contacts: std.ArrayList(physics.Contact),
    seed: u64 = 0,
    client_state: ClientState,
    allocator: *std.mem.Allocator,
    particle_count: u32 = 0,
    sim_start_time: i64,
    player_index: u32 = undefined,
    sun_index: u32 = undefined,
    logic_func: *fn () void = undefined,
};

const ENGINE_NAME = "CeresVoxel";

var input_state = InputState{};

// Current mouse state (Must be global so it can be accessed by the mouse input callback)
var xpos: f64 = 0.0;
var ypos: f64 = 0.0;
var dx: f64 = 0.0;
var dy: f64 = 0.0;

const EngineState = struct {
    allocator: *std.mem.Allocator,
    vulkan_state: *vulkan.VulkanState,
    world_state: *GameState,
};

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
    var allocator = gpa.allocator(); //arena.allocator();

    if (std.debug.runtime_safety) {
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

    try vulkan.render_init(&vulkan_state, "CeresVoxel");

    // GLFW Callbacks
    _ = c.vulkan.glfwSetKeyCallback(vulkan_state.window, key_callback);

    _ = c.vulkan.glfwSetCursorPosCallback(vulkan_state.window, cursor_pos_callback);
    _ = c.vulkan.glfwSetWindowUserPointer(vulkan_state.window, @constCast(&vulkan_state));
    _ = c.vulkan.glfwSetFramebufferSizeCallback(vulkan_state.window, window_resize_callback);
    _ = c.vulkan.glfwSetMouseButtonCallback(vulkan_state.window, mouse_button_input_callback);

    // game and physics INIT

    var sandbox_game_state = GameState{
        .client_state = ClientState{},
        .allocator = &allocator,
        .sim_start_time = std.time.milliTimestamp(),
        .objects = try std.ArrayList(Object).initCapacity(allocator, 100),
        .contacts = try std.ArrayList(physics.Contact).initCapacity(allocator, 2000),
    };
    try sandbox_state_init(&sandbox_game_state, &allocator);
    defer sandbox_game_state.objects.deinit(allocator);
    defer sandbox_game_state.contacts.deinit(allocator);

    var test_game_state = GameState{
        .client_state = ClientState{},
        .allocator = &allocator,
        .sim_start_time = std.time.milliTimestamp(),
        .objects = try std.ArrayList(Object).initCapacity(allocator, 100),
        .contacts = try std.ArrayList(physics.Contact).initCapacity(allocator, 2000),
    };
    defer test_game_state.objects.deinit(allocator);
    defer test_game_state.contacts.deinit(allocator);

    var engine_state = EngineState{
        .allocator = &allocator,
        .world_state = &sandbox_game_state,
        .vulkan_state = &vulkan_state,
    };

    try load_game_state(&engine_state, &sandbox_game_state);

    // Game Loop and additional prerequisites

    var prev_time: i64 = 0;
    var prev_time_micro: i64 = 0;
    const MINIMUM_PHYSICS_TICK_TIME: i64 = 10;
    // const MINIMUM_RENDER_TICK_TIME: i64 = 0;

    var frame_count: u64 = 0;
    var current_frame_index: u32 = 0;

    var window_height: i32 = 0;
    var window_width: i32 = 0;

    // Time in milliseconds in between frames, 60 is 16.666, 0.0 is
    var fps_limit: f32 = 0.0; //3.03030303;//8.333;
    _ = &fps_limit;

    // var fps_average: f32 = 0.0;
    var average_frame_dt: f32 = 0; // ms

    std.debug.print("fps limit: {}\n", .{fps_limit});

    var current_render_targets = try std.ArrayList(vulkan.RenderInfo).initCapacity(allocator, 200);
    var prev_physics_tick_time: i64 = std.time.milliTimestamp();

    var contact_renders = try std.ArrayList(physics.RenderContact).initCapacity(allocator, 1000);
    // var running_physics_tests: bool = false;

    var frame_objects: std.ArrayList(Object) = try std.ArrayList(Object).initCapacity(allocator, 2000);

    const pause_physics: bool = false;

    // The responsibility of the main thread is to handle input and manage
    // all the other threads
    // This will ensure the lowest input state for the various threads and have slightly
    // better seperation of responsiblities
    // Camera state (yaw, pitch, and freecam) are all handled here as well
    while (c.vulkan.glfwWindowShouldClose(vulkan_state.window) == 0) {
        const current_time_micro: i64 = std.time.microTimestamp();
        const delta_time_micro: i64 = current_time_micro - prev_time_micro;
        const current_time: i64 = std.time.milliTimestamp();
        // const delta_time: i64 = current_time - prev_time;
        // const delta_time_float: f64 = @as(f64, @floatFromInt(delta_time)) / 1000.0; // seconds
        const delta_time_physics: i64 = current_time - prev_physics_tick_time;

        c.vulkan.glfwPollEvents();

        const client_state: *ClientState = &engine_state.world_state.client_state;
        const game_state: *GameState = engine_state.world_state;
        // if (input_state.equal) {
        //     print_mode = (print_mode + 1) % 3;
        //     input_state.equal = false;
        // }

        // if (input_state.minus) {
        //     //print_mode = (print_mode + 2) % 3;
        //     selected_object = (selected_object + 1) % @as(u32, @intCast(game_state.objects.items.len));
        //     input_state.minus = false;
        // }

        // if (input_state.p and print_mode > 0) {
        //     if (edit_mode and print_mode == 1) {
        //         game_state.objects.items[selected_object].orientation = zm.normalize4(game_state.objects.items[selected_object].orientation);
        //     }
        //     edit_mode = !edit_mode;
        //     input_state.p = false;
        // }

        // if (input_state.tab and edit_mode) {
        //     var edit_index_max: u32 = 0;
        //     if (print_mode == 1) {
        //         edit_index_max = 4;
        //     }
        //     if (print_mode == 2) {
        //         edit_index_max = 3;
        //     }
        //     edit_index = (edit_index + 1) % edit_index_max;
        //     input_state.tab = false;
        // }

        // if (input_state.i and edit_mode) {
        //     switch (print_mode) {
        //         1 => {
        //             game_state.objects.items[selected_object].orientation[edit_index] += 0.1;
        //         },
        //         2 => {
        //             if (edit_index > 3) edit_index = 0;
        //             game_state.objects.items[selected_object].position[edit_index] += 0.1;
        //         },
        //         else => {},
        //     }
        //     input_state.i = false;
        // }

        // if (input_state.o and edit_mode) {
        //     switch (print_mode) {
        //         1 => {
        //             game_state.objects.items[selected_object].orientation[edit_index] -= 0.1;
        //             //game_state.objects / 1000.items[selected_object].orientation[edit_index] -= std.math.pi * 0.1;
        //             //game_state.objects.items[selected_object].orientation = zm.normalize4(game_state.objects.items[selected_object].orientation);
        //         },
        //         2 => {
        //             if (edit_index > 3) edit_index = 0;
        //             game_state.objects.items[selected_object].position[edit_index] -= 0.1;
        //         },
        //         else => {},
        //     }
        //     input_state.o = false;
        // }

        // if (edit_mode) {
        //     //game_state.objects.items[selected_object].colliding = CollisionType.PLAYER_SELECT;
        // }

        if (input_state.one) {
            try load_game_state(&engine_state, &sandbox_game_state);
            input_state.one = false;
        }
        if (input_state.two) {
            test_game_state.objects.clearRetainingCapacity();
            try physics_test1_game_state(&test_game_state, &allocator);
            try load_game_state(&engine_state, &test_game_state);
            input_state.two = false;
        }
        if (input_state.three) {
            test_game_state.objects.clearRetainingCapacity();
            try physics_test2_game_state(&test_game_state, &allocator);
            try load_game_state(&engine_state, &test_game_state);
            input_state.three = false;
        }
        if (input_state.four) {
            test_game_state.objects.clearRetainingCapacity();
            try physics_test5_game_state(&test_game_state, &allocator);
            try load_game_state(&engine_state, &test_game_state);
            input_state.four = false;
        }
        if (input_state.five) {
            test_game_state.objects.clearRetainingCapacity();
            try physics_test4_game_state(&test_game_state, &allocator);
            try load_game_state(&engine_state, &test_game_state);
            input_state.five = false;
        }

        if (input_state.control) {
            client_state.free_cam_speed = 100.0;
        } else {
            client_state.free_cam_speed = 5.0;
        }

        if (@abs(input_state.mouse_dx) > 0.0 and input_state.mouse_capture) {
            client_state.yaw -= @as(f32, @floatCast(input_state.mouse_dx * std.math.pi / 180.0 * input_state.MOUSE_SENSITIVITY));
            input_state.mouse_dx = 0.0;
        }

        if (@abs(input_state.mouse_dy) > 0.0 and input_state.mouse_capture) {
            client_state.pitch += @as(f32, @floatCast(input_state.mouse_dy * std.math.pi / 180.0 * input_state.MOUSE_SENSITIVITY));
            if (client_state.pitch >= std.math.pi / 2.0 - std.math.pi / 256.0) {
                client_state.pitch = std.math.pi / 2.0 - std.math.pi / 256.0;
            }
            if (client_state.pitch < -std.math.pi / 2.0 + std.math.pi / 256.0) {
                client_state.pitch = -std.math.pi / 2.0 + std.math.pi / 256.0;
            }
            input_state.mouse_dy = 0.0;
        }

        input_state.scroll_dy = 0.0;

        const look = client_state.lookV();
        const up = client_state.up();
        const right = client_state.right();

        var input_vec: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 };

        if (input_state.space) {
            input_vec -= cm.scale_f32(up, client_state.free_cam_speed);
        }
        if (input_state.shift) {
            input_vec += cm.scale_f32(up, client_state.free_cam_speed);
        }
        if (input_state.w) {
            input_vec += cm.scale_f32(look, client_state.free_cam_speed);
        }
        if (input_state.s) {
            input_vec -= cm.scale_f32(look, client_state.free_cam_speed);
        }
        if (input_state.d) {
            input_vec += cm.scale_f32(right, client_state.free_cam_speed);
        }
        if (input_state.a) {
            input_vec -= cm.scale_f32(right, client_state.free_cam_speed);
        }

        if (input_state.mouse_capture) {
            c.vulkan.glfwSetInputMode(vulkan_state.window, c.vulkan.GLFW_CURSOR, c.vulkan.GLFW_CURSOR_DISABLED);
        } else {
            c.vulkan.glfwSetInputMode(vulkan_state.window, c.vulkan.GLFW_CURSOR, c.vulkan.GLFW_CURSOR_NORMAL);
        }

        // if (input_state.g) {
        //     if (pause_physics) {
        //         prev_physics_tick_time = prev_time;
        //     }
        //     pause_physics = !pause_physics;
        //     input_state.g = false;
        //     // engine_state.world_state = &test_state;
        // }

        if (delta_time_physics > MINIMUM_PHYSICS_TICK_TIME and !pause_physics) {
            // PHYSICS AND LOGIC SECTION

            prev_physics_tick_time = current_time;

            const player_physics_state: *Object = &game_state.objects.items[game_state.player_index];

            // TODO need to add some way for this to be done in the logic loop
            player_physics_state.*.velocity = input_vec;

            // TODO this should be in the logic loop as well
            // for (game_state.objects.items, 0..game_state.objects.items.len) |body, index| {
            //     if (body.body_type == .particle) {
            //         const MAX_PARTICLE_TIME: u32 = 200;
            //         if (body.particle_time < MAX_PARTICLE_TIME) {
            //             game_state.objects.items[index].particle_time += 1;
            //         } else {
            //             _ = game_state.objects.orderedRemove(index);
            //             game_state.particle_count -= 1;
            //         }
            //     }
            // }

            // TODO this should be in the logic loop not in the physics loop
            // if (input_state.e and current_time - vomit_cooldown_previous_time > VOMIT_COOLDOWN) {
            //     const client_look_dir = game_state.client_state.lookV();
            //     const particle_start_pos: @Vector(3, f128) = .{
            //         player_physics_state.*.position[0] + (client_look_dir[0] * 2.0),
            //         player_physics_state.*.position[1] + (client_look_dir[1] * 2.0),
            //         player_physics_state.*.position[2] + (client_look_dir[2] * 2.0),
            //     };
            //     try game_state.objects.append(allocator, .{
            //         .position = particle_start_pos,
            //         .inverse_mass = 1.0 / 5.0,
            //         .orientation = game_state.client_state
            //             .look(),
            //         .velocity = cm.scale_f32(client_look_dir, 1.0 * 32.0) + player_physics_state.*.velocity,
            //         //.angular_velocity = .{1.0,0.0,0.0,0.0},
            //         .half_size = .{ 0.125, 0.125, 0.125, 0.0 },
            //         .body_type = .particle,
            //     });

            //     game_state.particle_count += 1;

            //     vomit_cooldown_previous_time = current_time;
            // }

            // TODO throw this into a different thread and join when the tick is done
            try physics.physics_tick(
                @as(f32, @floatFromInt(delta_time_physics)) / 1000.0,
                game_state.sim_start_time,
                game_state.objects.items,
                &game_state.contacts,
            );

            contact_renders.clearRetainingCapacity();
            // Get contact render info
            for (game_state.contacts.items) |contact| {
                const cast_body_pos: zm.Vec = .{
                    @as(f32, @floatCast(contact.B.position[0] - player_physics_state.position[0])),
                    @as(f32, @floatCast(contact.B.position[1] - player_physics_state.position[1])),
                    @as(f32, @floatCast(contact.B.position[2] - player_physics_state.position[2])),
                    0.0,
                };
                contact_renders.appendAssumeCapacity(.{
                    .normal = contact.normal,
                    .position = cast_body_pos + contact.pB,
                });
            }
            // contact_count = @intCast(contacts.items.len);
            game_state.contacts.clearRetainingCapacity();
        }

        //_ = &MINIMUM_RENDER_TICK_TIME;
        // if (delta_time > MINIMUM_RENDER_TICK_TIME) {
        prev_time = current_time;
        prev_time_micro = current_time_micro;
        try frame_objects.appendSliceBounded(game_state.objects.items);
        // @memcpy(frame_objects[0..game_state.objects.items.len], game_state.objects.items);
        // _ = &frame_objects;

        const chunk_render_targets = try generate_chunk_render_targets(&allocator, game_state.objects.items);
        current_render_targets.appendSliceAssumeCapacity(vulkan_state.render_targets.items);
        current_render_targets.appendSliceAssumeCapacity(chunk_render_targets);

        // TODO make the integrator slightly more predicitvie some how?
        // updated_objects = try allocator.realloc(updated_objects, game_state.objects.items.len);
        // @memcpy(updated_objects, game_state.objects.items);

        // Lower the percieved latency on player input
        // updated_objects[game_state.player_index].velocity = input_vec;
        // physics.euler_integration(frame_objects, physics_delta_time);

        var render_frame = vulkan.RenderFrame{
            .render_targets = current_render_targets.items,
            .bodies = frame_objects.items,
            .contact_renders = contact_renders.items,
            .particle_count = game_state.particle_count,
            .player_index = game_state.player_index,
            .client_state = &game_state.client_state,
        };

        c.vulkan.glfwGetWindowSize(vulkan_state.window, &window_width, &window_height);
        const aspect_ratio: f32 = @as(f32, @floatFromInt(window_width)) / @as(f32, @floatFromInt(window_height));

        const player_pos: zm.Vec = .{ 0.0, -0.45, 0.0, 0.0 };
        const view: zm.Mat = zm.lookToLh(player_pos, look, up);
        const projection: zm.Mat = zm.perspectiveFovLh(1.0, aspect_ratio, 0.1, 1000.0);
        const view_proj: zm.Mat = zm.mul(view, projection);

        @memcpy(vulkan_state.push_constant_data[0..64], @as([]u8, @ptrCast(@constCast(&view_proj)))[0..64]);
        @memcpy(vulkan_state.push_constant_data[@sizeOf(zm.Mat)..(@sizeOf(zm.Mat) + 4)], @as([*]u8, @ptrCast(@constCast(&aspect_ratio)))[0..4]);
        @memset(vulkan_state.push_constant_data[(@sizeOf(zm.Mat) + 4)..(@sizeOf(zm.Mat) + 4 + 4)], 0);

        try vulkan.update_chunk_ubo(
            &vulkan_state,
            render_frame.bodies,
            render_frame.player_index,
            1,
        );

        // TODO make it so outlines can be enabled or disabled
        try vulkan.update_outline_ubo(
            &vulkan_state,
            render_frame.bodies,
            render_frame.contact_renders,
            render_frame.player_index,
            0,
        );

        const box_count: usize = render_frame.bodies.len + render_frame.contact_renders.len;
        vulkan_state.render_targets.items[1].instance_count = @intCast(box_count);
        vulkan_state.render_targets.items[2].instance_count = @intCast(render_frame.contact_renders.len);
        vulkan_state.render_targets.items[2].first_instance = @intCast(box_count);

        // DRAW
        try vulkan_state.draw_frame(current_frame_index, &render_frame.render_targets);

        // TODO make the position printed the camera position
        std.debug.print("[G] {d:5.3}ms {d:4.1}fps pos:{d:3.1} {d:3.1} {d:3.1} y:{d:3.1} p:{d:3.1}   [{s}]   \r", .{
            average_frame_dt,
            1.0 / average_frame_dt * 1000.0,
            client_state.camera_pos[0], // @as(f32, @floatCast(render_frame.bodies[render_frame.player_index].position[0])),
            client_state.camera_pos[1], // @as(f32, @floatCast(render_frame.bodies[render_frame.player_index].position[1])),
            client_state.camera_pos[2], // @as(f32, @floatCast(render_frame.bodies[render_frame.player_index].position[2])),
            render_frame.client_state.yaw,
            render_frame.client_state.pitch,
            if (pause_physics) "P" else ">",
        });

        // EMA fps and delta_time
        const alpha: f32 = 0.5;
        average_frame_dt = alpha * @as(f32, @floatFromInt(delta_time_micro)) / 1000.0 + (1 - alpha) * average_frame_dt;
        // fps_average = @as(f32, @floatCast(alpha * delta_time_float)) + (1 - alpha) * fps_average;

        current_frame_index = (current_frame_index + 1) % vulkan_state.MAX_CONCURRENT_FRAMES;
        frame_count += 1;
        // }

        //contacts.clearRetainingCapacity();
        current_render_targets.clearRetainingCapacity();
        frame_objects.clearRetainingCapacity();
    }

    frame_objects.clearAndFree(allocator);
    _ = c.vulkan.vkDeviceWaitIdle(vulkan_state.device);
    vulkan_state.cleanup();
}

pub export fn key_callback(
    window: ?*c.vulkan.GLFWwindow,
    key: i32,
    scancode: i32,
    action: i32,
    mods: i32,
) void {
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
                if (input_state.mouse_capture == true) {
                    input_state.mouse_capture = false;
                } else {
                    input_state.mouse_capture = true;
                }
            }
        },
        c.vulkan.GLFW_KEY_P => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.p = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.p = false;
            }
        },
        c.vulkan.GLFW_KEY_EQUAL => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.equal = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.equal = false;
            }
        },
        c.vulkan.GLFW_KEY_MINUS => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.minus = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.minus = false;
            }
        },
        c.vulkan.GLFW_KEY_TAB => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.tab = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.tab = false;
            }
        },
        c.vulkan.GLFW_KEY_I => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.i = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.i = false;
            }
        },
        c.vulkan.GLFW_KEY_O => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.o = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.o = false;
            }
        },
        c.vulkan.GLFW_KEY_G => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.g = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.g = false;
            }
        },
        c.vulkan.GLFW_KEY_1 => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.one = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.one = false;
            }
        },
        c.vulkan.GLFW_KEY_2 => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.two = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.two = false;
            }
        },
        c.vulkan.GLFW_KEY_3 => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.three = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.three = false;
            }
        },
        c.vulkan.GLFW_KEY_4 => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.four = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.four = false;
            }
        },
        c.vulkan.GLFW_KEY_5 => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.five = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.five = false;
            }
        },
        else => {},
    }
}

pub export fn cursor_pos_callback(
    window: ?*c.vulkan.GLFWwindow,
    _xpos: f64,
    _ypos: f64,
) void {
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

pub export fn mouse_button_input_callback(
    window: ?*c.vulkan.GLFWwindow,
    button: i32,
    action: i32,
    mods: i32,
) void {
    _ = &button;
    _ = &window;
    _ = &mods;

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

pub export fn mouse_scroll_input_callback(
    window: ?*c.vulkan.GLFWwindow,
    xoffset: f64,
    yoffset: f64,
) void {
    _ = &window;
    _ = &xoffset;

    input_state.scroll_dy += yoffset;
}

pub export fn window_resize_callback(
    window: ?*c.vulkan.GLFWwindow,
    width: c_int,
    height: c_int,
) void {
    _ = &width;
    _ = &height;
    const instance: *vulkan.VulkanState = @ptrCast(@alignCast(c.vulkan.glfwGetWindowUserPointer(window)));
    instance.framebuffer_resized = true;
}

pub fn generate_chunk_render_targets(
    allocator: *std.mem.Allocator,
    objects: []Object,
) ![]vulkan.RenderInfo {
    var list = try std.ArrayList(vulkan.RenderInfo).initCapacity(allocator.*, 10);
    defer list.deinit(allocator.*);

    // TODO add culling algorithms
    var chunk_index: u32 = 0;
    for (objects) |object| {
        if (object.body_type == .voxel_space) {
            for (object.chunks.items) |chunk_data| {
                if (chunk_data.empty == false) {
                    try list.append(allocator.*, vulkan.RenderInfo{
                        .vertex_buffer = chunk_data.vertex_buffer.buffer,
                        .pipeline_index = 2,
                        .vertex_count = chunk_data.vertex_buffer.vertex_count,
                        .push_constant_index = chunk_index,
                    });
                    chunk_index += 1;
                }
            }
        }
    }

    return try list.toOwnedSlice(allocator.*);
}

/// Generate a bitmask according to which chunks we want to be loaded in our voxel space
//pub fn generate_chunk_occupancy_mask(obj: Object) ![]u32 {
//    var
//}

/// decides which chunks to load
pub fn load_chunk(
    allocator: std.mem.Allocator,
    game_state: *GameState,
    obj: *Object,
) !void {
    for (0..(obj.size[0] * obj.size[1] * obj.size[2])) |chunk_index| {
        _ = &chunk_index;
        _ = &game_state;
        const data = try chunk.get_chunk_data_sun(); //game_state.seed + chunk_index);
        const chunk_data = chunk.Chunk{
            .empty = false,
            .block_occupancy = undefined,
            .blocks = data,
        };
        try obj.chunks.append(allocator, chunk_data);
    }
}

/// sandbox world template (plan for the survival world template)
fn sandbox_state_init(game_state: *GameState, allocator: *std.mem.Allocator) !void {
    // player
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.0, -128.0 },
        .inverse_mass = (1.0 / 100.0),
        .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
        .body_type = .player,
    });
    game_state.player_index = @intCast(game_state.objects.items.len - 1);

    // "Sun"
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 10000000.0,
        .planet = false,
        .gravity = false,
        .size = .{ 1, 1, 1 }, // 32 * 3 / 2
        .half_size = .{ 16, 16, 16, 0.0 },
        .body_type = .voxel_space,
        .chunks = try std.ArrayList(chunk.Chunk).initCapacity(allocator.*, 10), // 10 chunks
        .chunk_occupancy = try std.ArrayList(u32).initCapacity(allocator.*, 32), // binary field of which chunks are to be loaded which ones not to.
        .lock_rot = true,
    });
    game_state.sun_index = @intCast(game_state.objects.items.len - 1);
    std.debug.print("sun weight: {}\n", .{1.0 / game_state.objects.getLast().inverse_mass});

    // Test Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 128.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 1000.0,
        .planet = false,
        .gravity = false,
        .half_size = .{ 1, 1, 1, 0.0 },
        .body_type = .other,
    });
}

fn physics_test1_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
    // player
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.0, -16.0 },
        .inverse_mass = (1.0 / 100.0),
        .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
        .body_type = .player,
    });
    game_state.player_index = @intCast(game_state.objects.items.len - 1);

    // Test1 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 1000.0,
        .planet = false,
        .gravity = false,
        .half_size = .{ 1, 1, 1, 0.0 },
        .body_type = .other,
    });

    // Test2 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 5.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 1000.0,
        .planet = false,
        .velocity = .{ -1.0, 0.0, 0.0, 0.0 },
        .gravity = false,
        .half_size = .{ 1, 1, 1, 0.0 },
        .body_type = .other,
    });
}

fn physics_test2_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
    // player
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.0, -16.0 },
        .inverse_mass = (1.0 / 100.0),
        .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
        .body_type = .player,
    });
    game_state.player_index = @intCast(game_state.objects.items.len - 1);

    // Test1 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 1000.0,
        .planet = false,
        .gravity = false,
        .half_size = .{ 1, 1, 1, 0.0 },
        .body_type = .other,
    });

    // Test2 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 5.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 1000.0,
        .planet = false,
        .velocity = .{ -5.0, 0.0, 0.0, 0.0 },
        .gravity = false,
        .half_size = .{ 1, 1, 1, 0.0 },
        .body_type = .other,
    });
}

fn physics_test3_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
    // player
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.0, -16.0 },
        .inverse_mass = (1.0 / 100.0),
        .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
        .body_type = .player,
    });
    game_state.player_index = @intCast(game_state.objects.items.len - 1);

    // Test1 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 1000.0,
        .planet = false,
        .gravity = false,
        .half_size = .{ 1, 1, 1, 0.0 },
        .body_type = .other,
    });

    // Test2 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 5.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 5.0,
        .velocity = .{ -5.0, 0.0, 0.0, 0.0 },
        .planet = false,
        .gravity = false,
        .half_size = .{ 0.125, 0.125, 0.125, 0.0 },
        .body_type = .other,
    });
}

// Newtons Cradle
fn physics_test4_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
    // player
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.0, -8.0 },
        .inverse_mass = (1.0 / 100.0),
        .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
        .body_type = .player,
    });
    game_state.player_index = @intCast(game_state.objects.items.len - 1);

    // Test1 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 1000.0,
        .planet = false,
        .gravity = false,
        .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
        .body_type = .other,
    });

    // Test2 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 1.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 5.0,
        .velocity = .{ 0.0, 0.0, 0.0, 0.0 },
        .planet = false,
        .gravity = false,
        .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
        .body_type = .other,
    });

    // Test3 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 3.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 5.0,
        .velocity = .{ -6.0, 0.0, 0.0, 0.0 },
        .planet = false,
        .gravity = false,
        .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
        .body_type = .other,
    });
}

// Bernoulli's Problem
fn physics_test5_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
    // player
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.0, -8.0 },
        .inverse_mass = (1.0 / 100.0),
        .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
        .body_type = .player,
    });
    game_state.player_index = @intCast(game_state.objects.items.len - 1);

    // Test1 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, -0.5, 0.0 },
        .inverse_mass = 1.0 / 1000.0,
        .planet = false,
        .gravity = false,
        .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
        .body_type = .other,
    });

    // Test2 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 0.0, 0.5, 0.0 },
        .inverse_mass = 1.0 / 5.0,
        .velocity = .{ 0.0, 0.0, 0.0, 0.0 },
        .planet = false,
        .gravity = false,
        .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
        .body_type = .other,
    });

    // Test3 Box
    try game_state.objects.append(allocator.*, .{
        .position = .{ 4.0, 0.0, 0.0 },
        .inverse_mass = 1.0 / 5.0,
        .velocity = .{ -6.0, 0.0, 0.0, 0.0 },
        .planet = false,
        .gravity = false,
        .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
        .body_type = .other,
    });
}

fn load_game_state(
    engine_state: *EngineState,
    game_state: *GameState,
) !void {
    var start_load_time = std.time.milliTimestamp();

    for (0..engine_state.world_state.*.objects.items.len) |obj_index| {
        if (engine_state.world_state.*.objects.items[obj_index].body_type == .voxel_space) {
            try load_chunk(game_state.allocator.*, engine_state.world_state, &engine_state.world_state.*.objects.items[obj_index]);
        }
    }
    std.debug.print("[Debug] Loading chunks {}ms\n", .{std.time.milliTimestamp() - start_load_time});

    start_load_time = std.time.milliTimestamp();

    var chunk_count: i32 = 0;
    for (engine_state.world_state.*.objects.items) |object| {
        if (object.body_type == .voxel_space) {
            for (0..object.chunks.items.len) |chunk_index| {
                const start_chunk_mesh_time = std.time.milliTimestamp();

                const chunk_mesh = try mesh_generation.CullMesh(
                    &object.chunks.items[chunk_index].blocks,
                    game_state.allocator,
                );
                object.chunks.items[chunk_index].vertex_buffer = try vulkan.VulkanState.create_vertex_buffer(
                    engine_state.vulkan_state,
                    @sizeOf(vulkan.ChunkVertex),
                    @intCast(chunk_mesh.len * @sizeOf(vulkan.ChunkVertex)),
                    &chunk_mesh[0],
                );
                chunk_count += 1;
                game_state.allocator.free(chunk_mesh);

                std.debug.print("chunk_index: {} | chunk mesh time: {}ms | chunk count: {}\n", .{
                    chunk_index,
                    std.time.milliTimestamp() - start_chunk_mesh_time,
                    chunk_count,
                });
            }
        }
    }
    std.debug.print("[Debug] Generating chunk meshes {}ms\n", .{std.time.milliTimestamp() - start_load_time});

    engine_state.world_state = game_state;
}

fn unload_game_state(
    engine_state: *EngineState,
    game_state: *GameState,
) void {
    for (0..game_state.objects.items.len) |object_index| {
        if (game_state.objects.items[object_index].body_type == .voxel_space) {
            game_state.objects.items[object_index].chunks.deinit(engine_state.allocator);
        }
    }
}
