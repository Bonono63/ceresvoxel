//!Main entry point for CeresVoxel
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");
const zm = @import("zmath");
const chunk = @import("chunk.zig");
const physics = @import("physics.zig");
const cm = @import("ceresmath.zig");
const mesh_generation = @import("mesh_generation.zig");
const zphy = @import("zphysics");

pub const InputState = packed struct {
    MOUSE_SENSITIVITY: f64 = 0.1,
    player_forward: bool = false,
    player_backwards: bool = false,
    player_left: bool = false,
    player_right: bool = false,
    player_roll_left: bool = false, // only used when in space
    player_roll_right: bool = false, // only used when in space
    jump: bool = false,
    crouch: bool = false,
    sprint: bool = false,
    interact: bool = false,

    toggle_free_cam: bool = false,
    mouse_capture: bool = true,
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
    camera_pos: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 },
    camera_up: zm.Vec = .{ 0.0, -1.0, 0.0, 0.0 },

    const defualt_up = zm.Vec{ 0.0, -1.0, 0.0, 0.0 };

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

    //     return result;
    // }

    // pub fn up(self: *const ClientState) zm.Vec {
    //     _ = &self;
    //     return .{ 0.0, -1.0, 0.0, 0.0 };
    // }

    // pub fn right(self: *const ClientState) zm.Vec {
    //     return zm.normalize3(zm.cross3(self.up(), self.lookV()));
    // }
};

pub const Type = enum {
    voxel_space, // any collection of voxels
    player,
    planet,
    other, // just for testing
};

// pub const CollisionType = enum {
//     NONE,
//     COLLISION,
//     PLAYER_SELECT,
// };

pub const Block = enum {
    AIR,
    ANDESITE,
    GRANITE,
    CORE_0,
    CORE_1,
    LOG_0,
    LOG_1,
    LEAVES,
    ROCK,
};

/// UUID v7 storage and helpers
pub const UUID = struct {
    data: [16]u8 = undefined,

    pub fn init() UUID {
        var result: UUID = undefined;
        const seed0: i128 = std.time.nanoTimestamp(); // this seed is probably fine right????
        const seed1: i128 = std.time.nanoTimestamp(); // this seed is probably fine right????
        var seed: [32]u8 = undefined;
        @memcpy(seed[0..16], @as([]u8, @ptrCast(@constCast(&seed0))));
        @memcpy(seed[16..32], @as([]u8, @ptrCast(@constCast(&seed1))));
        var chacha = std.Random.DefaultCsprng.init(seed);
        chacha.fill(result.data[6..]); // all random bytes
        // time stamp
        const time: i64 = std.time.milliTimestamp();
        @memcpy(result.data[0..6], @as([]u8, @ptrCast(@constCast(&time)))[0..6]);
        // std.debug.print("{x}\n", .{result.data[0..6]});
        // version byte
        result.data[7] = result.data[7] | 0b11110000 ^ 0b10000000;
        // std.debug.print("{x} {b:0>8}\n", .{ result.data[7], result.data[7] });
        // variant bits
        result.data[9] = result.data[9] | 0b11000000 ^ 0b01000000;
        // std.debug.print("{x} {b:0>8}\n", .{ result.data[9], result.data[9] });
        // std.debug.print("{x}-{x}-{x}-{x}-{x}\n", .{ result.data[0..4], result.data[4..6], result.data[7..9], result.data[9..11], result.data[12..] });
        return result;
    }

    // pub fn toString() []u8 {

    // }

    /// compares 2 UUIDs, although this is likely not needed
    pub fn compare(self: *UUID, other: *UUID) bool {
        var result: bool = true;

        for (0..self.data.len) |i| {
            if (other.data[i] != self.data[i]) {
                result = false;
            }
        }

        return result;
    }
};

pub const Object = struct {
    body_type: Type,

    physics_id: zphy.BodyId,
    physics_settings: *zphy.ShapeSettings,
    physics_shape: *zphy.Shape,

    /// Block distance from the center of the planet where the geologic crust begins
    crust_distance: u32 = 0,
    /// Coefficient for when different crust layers start
    planet_age: f32 = 0.0, // [-1.0, 1.0]

    // orbit_radius: f128 = 0.0,
    // barycenter: @Vector(2, f128) = .{ 0.0, 0.0 },
    // eccliptic_offset: @Vector(2, f32) = .{ 0.0, 0.0 },

    // size: @Vector(3, u32) = .{ 0, 0, 0 },
    chunks: std.AutoArrayHashMap(@Vector(3, u32), chunk.Chunk) = undefined,

    /// Collected from the physics system and cached for the rest of the frame
    render_transform: zm.Mat = zm.identity(),

    // /// Returns the object's transform (for rendering or physics)
    // /// for safety reasons should only be called on objects within f32's range.
    // pub fn transform(self: *const Object) zm.Mat {
    //     var result: zm.Mat = zm.identity();
    //     const half_offset = zm.translationV(cm.scale_f32(self.half_size, -1.0));
    //     const world_pos = zm.translationV(.{
    //         @as(f32, @floatCast(self.position[0])),
    //         @as(f32, @floatCast(self.position[1])),
    //         @as(f32, @floatCast(self.position[2])),
    //         0.0,
    //     });
    //     result = zm.mul(result, half_offset);
    //     result = zm.mul(result, zm.matFromQuat(self.orientation));
    //     result = zm.mul(result, world_pos);
    //     return result;
    // }

    // /// Returns the object's transform (for rendering or physics)
    // pub fn render_transform(self: *const Object, player_pos: @Vector(3, f128)) zm.Mat {
    //     var result: zm.Mat = zm.identity();
    //     const half_offset = zm.translationV(cm.scale_f32(self.half_size, -1.0));
    //     const world_pos = zm.translationV(.{
    //         @as(f32, @floatCast(self.position[0] - player_pos[0])),
    //         @as(f32, @floatCast(self.position[1] - player_pos[1])),
    //         @as(f32, @floatCast(self.position[2] - player_pos[2])),
    //         0.0,
    //     });
    //     const scale = zm.matFromArr(.{
    //         self.half_size[0], 0.0, 0.0, 0.0, //
    //         0.0, self.half_size[1], 0.0, 0.0, //
    //         0.0, 0.0, self.half_size[2], 0.0, //
    //         0.0, 0.0, 0.0, 0.5, //
    //     });
    //     result = zm.mul(result, scale);
    //     result = zm.mul(result, half_offset);
    //     result = zm.mul(result, zm.matFromQuat(self.orientation));
    //     result = zm.mul(result, world_pos);
    //     return result;
    // }

    // /// Returns the object's transform (for rendering or physics)
    // /// for safety reasons should only be called on objects within f32's range.
    // pub fn render_transform_chunk(self: *const Object, player_pos: @Vector(3, f128), chunk_index: u32) zm.Mat {
    //     var result: zm.Mat = zm.identity();
    //     const half_offset: zm.Mat = zm.translationV(.{
    //         -self.half_size[0],
    //         -self.half_size[1],
    //         -self.half_size[2],
    //         0.0,
    //     });
    //     const chunk_offset: zm.Mat = zm.translationV(.{
    //         @as(f32, @floatFromInt(chunk_index % self.size[0] * 32)),
    //         @as(f32, @floatFromInt(chunk_index / self.size[0] % self.size[1] * 32)),
    //         @as(f32, @floatFromInt(chunk_index / self.size[0] / self.size[1] % self.size[2] * 32)),
    //         0.0,
    //     });
    //     const world_pos: zm.Mat = zm.translationV(.{
    //         @as(f32, @floatCast(self.position[0] - player_pos[0])),
    //         @as(f32, @floatCast(self.position[1] - player_pos[1])),
    //         @as(f32, @floatCast(self.position[2] - player_pos[2])),
    //         0.0,
    //     });
    //     result = zm.mul(result, half_offset);
    //     result = zm.mul(result, chunk_offset);
    //     result = zm.mul(result, zm.matFromQuat(self.orientation));
    //     result = zm.mul(result, world_pos);
    //     return result;
    // }
};

///Stores arbitrary state of the game
pub const GameState = struct {
    objects: std.AutoArrayHashMap(UUID, Object),
    seed: u64 = 0,
    client_state: ClientState,
    allocator: *std.mem.Allocator,
    sim_start_time: i64,
    playerUUID: UUID = undefined,
    playerPhysicsID: zphy.BodyId = undefined,
    /// there should instead be a list of solar systems and each one is has a sun and various planets. THEN orbital mechanics are applied to those objects instead of just one "sun"
    sunID: UUID = undefined,
    logic_tick: bool,
    physics_system: *zphy.PhysicsSystem,
    physics_params: physics.PhysicsSystemParameters,
    logic_func: *const fn (self: *GameState, delta_time: i64) void = undefined,
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

    var world_state = GameState{
        .client_state = ClientState{},
        .allocator = &allocator,
        .sim_start_time = std.time.milliTimestamp(),
        .objects = std.AutoArrayHashMap(UUID, Object).init(allocator),
        .logic_tick = false,
        .physics_system = undefined,
        .physics_params = undefined,
    };
    try physics.physics_init(allocator, &world_state.physics_system, &world_state.physics_params);
    try sandbox_state_init(&world_state);
    defer world_state.objects.deinit();

    var engine_state = EngineState{
        .allocator = &allocator,
        .world_state = &world_state,
        .vulkan_state = &vulkan_state,
    };

    try load_game_state(&engine_state, &world_state);

    // Game Loop and additional prerequisites

    var prev_time_micro: i64 = 0;
    const MINIMUM_PHYSICS_TICK_TIME: i64 = 10;
    const MINIMUM_LOGIC_TICK_TIME: i64 = 10;
    const MINIMUM_RENDER_TICK_TIME: i64 = 0; // microseconds

    var frame_count: u64 = 0;
    var current_frame_index: u32 = 0;

    var window_height: i32 = 0;
    var window_width: i32 = 0;

    // Time in milliseconds in between frames, 60 is 16.666, 0.0 is
    var fps_limit: f32 = 0.0; //3.03030303;//8.333;
    _ = &fps_limit;

    var average_frame_dt: f32 = 0; // ms

    std.debug.print("fps limit: {}\n", .{fps_limit});

    var current_render_targets = try std.ArrayList(vulkan.RenderInfo).initCapacity(allocator, 200);
    defer current_render_targets.deinit(allocator);
    var prev_physics_tick_time: i64 = std.time.milliTimestamp();
    var prev_logic_tick_time: i64 = std.time.milliTimestamp();

    var frame_objects: std.ArrayList(Object) = try std.ArrayList(Object).initCapacity(allocator, 2000);
    defer frame_objects.deinit(allocator);

    // The responsibility of the main thread is to handle input and manage
    // all the other threads
    // This will ensure the lowest input state for the various threads and have slightly
    // better seperation of responsiblities
    // Camera state (yaw, pitch, and freecam) are all handled here as well
    while (c.vulkan.glfwWindowShouldClose(vulkan_state.window) == 0) {
        const current_time_micro: i64 = std.time.microTimestamp();
        const delta_time_micro: i64 = current_time_micro - prev_time_micro;
        const current_time: i64 = std.time.milliTimestamp();
        const delta_time_physics: i64 = current_time - prev_physics_tick_time;
        const delta_time_logic: i64 = current_time - prev_logic_tick_time;

        c.vulkan.glfwPollEvents();

        const client_state: *ClientState = &engine_state.world_state.client_state;
        const game_state: *GameState = engine_state.world_state;

        {
            if (@abs(input_state.mouse_dx) > 0.0 and input_state.mouse_capture) {
                client_state.yaw -= @as(f32, @floatCast(input_state.mouse_dx * std.math.pi / 180.0 * input_state.MOUSE_SENSITIVITY));
                input_state.mouse_dx = 0.0;
            }

            if (@abs(input_state.mouse_dy) > 0.0 and input_state.mouse_capture) {
                client_state.pitch += @as(f32, @floatCast(input_state.mouse_dy * std.math.pi / 180.0 * input_state.MOUSE_SENSITIVITY));
                client_state.pitch = std.math.clamp(
                    client_state.pitch,
                    -std.math.pi / 2.0 + 0.0001,
                    std.math.pi / 2.0 - 0.0001,
                );
                input_state.mouse_dy = 0.0;
            }

            input_state.scroll_dy = 0.0;
        }

        if (input_state.mouse_capture) {
            c.vulkan.glfwSetInputMode(vulkan_state.window, c.vulkan.GLFW_CURSOR, c.vulkan.GLFW_CURSOR_DISABLED);
        } else {
            c.vulkan.glfwSetInputMode(vulkan_state.window, c.vulkan.GLFW_CURSOR, c.vulkan.GLFW_CURSOR_NORMAL);
        }

        // PHYSICS AND LOGIC SECTION
        if (delta_time_physics > MINIMUM_PHYSICS_TICK_TIME) {
            prev_physics_tick_time = current_time;

            game_state.physics_system.update(1.0 / 100.0, .{}) catch unreachable;
        }

        if (delta_time_logic > MINIMUM_LOGIC_TICK_TIME and engine_state.world_state.logic_tick) {
            prev_logic_tick_time = current_time;

            game_state.logic_func(
                game_state,
                delta_time_logic,
            );
        }

        if (delta_time_micro > MINIMUM_RENDER_TICK_TIME) {
            prev_time_micro = current_time_micro;

            // Locking should not be necessary given we are only reading data
            {
                const body_interface = game_state.physics_system.getBodyInterfaceNoLock();
                var objects = game_state.objects.values();
                for (objects, 0..objects.len) |object, index| {
                    const local_bounds = object.physics_shape.getLocalBounds().max;
                    const scale = zm.matFromArr(.{
                        -local_bounds[0], 0.0,              0.0,              0.0,
                        0.0,              -local_bounds[1], 0.0,              0.0,
                        0.0,              0.0,              -local_bounds[2], 0.0,
                        0.0,              0.0,              0.0,              0.5,
                    });
                    const half_offset = zm.translation(local_bounds[0], local_bounds[1], local_bounds[2]);
                    const pos = zm.translationV(zm.loadArr3(body_interface.getPosition(object.physics_id)));
                    const rot = zm.matFromQuat(zm.loadArr4(body_interface.getRotation(object.physics_id)));

                    var result = zm.identity();

                    result = zm.mul(result, scale);
                    result = zm.mul(result, half_offset);
                    result = zm.mul(result, rot);
                    result = zm.mul(result, pos);

                    objects[index].render_transform = result;
                }
            }

            try frame_objects.appendSliceBounded(game_state.objects.values());
            // physics interpolation
            // const time_since_last_physics_frame: f64 = @as(f64, @floatFromInt(current_time - prev_physics_tick_time)) / 1000.0;
            // physics.euler_integration(frame_objects.items, time_since_last_physics_frame);
            // frame_objects.items[game_state.player_index].velocity = input_vec;

            // const chunk_render_targets = try generate_chunk_render_targets(&allocator, game_state.objects.items);
            // defer allocator.free(chunk_render_targets);
            current_render_targets.appendSliceAssumeCapacity(vulkan_state.render_targets.items);
            // current_render_targets.appendSliceAssumeCapacity(chunk_render_targets);

            var render_frame = vulkan.RenderFrame{
                .render_targets = current_render_targets.items,
                .bodies = frame_objects.items,
                // .player_index = game_state.player_index,
                .client_state = &game_state.client_state,
            };

            c.vulkan.glfwGetWindowSize(vulkan_state.window, &window_width, &window_height);
            const aspect_ratio: f32 = @as(f32, @floatFromInt(window_width)) / @as(f32, @floatFromInt(window_height));

            const body_interface = game_state.physics_system.getBodyInterfaceMutNoLock();

            var camera_view_proj = zm.identity();

            const look = client_state.lookV();
            const player_pos: zm.Vec = zm.loadArr3(body_interface.getPosition(game_state.playerPhysicsID));
            const player_rot: zm.Quat = zm.loadArr4(body_interface.getRotation(game_state.playerPhysicsID));

            if (client_state.free_cam) {
                const view: zm.Mat = zm.lookToLh(client_state.camera_pos, look, .{ 0.0, -1.0, 0.0, 1.0 });
                const projection: zm.Mat = zm.perspectiveFovLh(1.0, aspect_ratio, 0.1, 1000.0);
                camera_view_proj = zm.mul(view, projection);
            } else {
                const player_rot_matrix = zm.matFromQuat(player_rot);
                const player_up_vec = zm.mul(zm.Vec{ 0.0, -1.0, 0.0, 1.0 }, player_rot_matrix);
                const player_look = zm.mul(look, player_rot_matrix);
                const player_camera_offset: zm.Vec = zm.mul(zm.Vec{ 0.0, 0.4, 0.0, 1.0 }, player_rot_matrix);
                const player_camera_pos: zm.Vec = player_pos + player_camera_offset;

                const view: zm.Mat = zm.lookToLh(player_camera_pos, player_look, player_up_vec);
                const projection: zm.Mat = zm.perspectiveFovLh(1.0, aspect_ratio, 0.1, 1000.0);
                camera_view_proj = zm.mul(view, projection);
            }

            @memcpy(vulkan_state.push_constant_data[0..64], @as([]u8, @ptrCast(@constCast(&camera_view_proj)))[0..64]);
            @memcpy(vulkan_state.push_constant_data[@sizeOf(zm.Mat)..(@sizeOf(zm.Mat) + 4)], @as([*]u8, @ptrCast(@constCast(&aspect_ratio)))[0..4]);
            @memset(vulkan_state.push_constant_data[(@sizeOf(zm.Mat) + 4)..(@sizeOf(zm.Mat) + 4 + 4)], 0);

            // try vulkan.update_chunk_ubo(
            //     &vulkan_state,
            //     render_frame.bodies,
            //     render_frame.player_index,
            //     1,
            // );

            // TODO make it so outlines can be enabled or disabled
            try vulkan.update_outline_ubo(
                &vulkan_state,
                render_frame.bodies,
                0,
            );

            const box_count: usize = render_frame.bodies.len;
            vulkan_state.render_targets.items[1].instance_count = @intCast(box_count);

            // DRAW
            try vulkan_state.draw_frame(current_frame_index, &render_frame.render_targets);

            // TODO make the position printed the camera position
            std.debug.print("[G] {d:5.3}ms {d:4.1}fps p: {d:4.1} {d:4.1} {d:4.1}\r", .{
                average_frame_dt,
                1.0 / average_frame_dt * 1000.0,
                player_pos[0],
                player_pos[1],
                player_pos[2],
            });

            // EMA fps and delta_time
            const alpha: f32 = 1.0;
            average_frame_dt = alpha * @as(f32, @floatFromInt(delta_time_micro)) / 1000.0 + (1 - alpha) * average_frame_dt;

            current_frame_index = (current_frame_index + 1) % vulkan_state.MAX_CONCURRENT_FRAMES;
            frame_count += 1;
        }

        current_render_targets.clearRetainingCapacity();
        frame_objects.clearRetainingCapacity();
    }

    unload_game_state(&engine_state);
    physics.physics_cleanup(allocator, engine_state.world_state.physics_system, engine_state.world_state.objects.values(), engine_state.world_state.physics_params);
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
                input_state.sprint = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.sprint = false;
            }
        },
        c.vulkan.GLFW_KEY_SPACE => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.jump = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.jump = false;
            }
        },
        c.vulkan.GLFW_KEY_LEFT_SHIFT => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.crouch = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.crouch = false;
            }
        },
        c.vulkan.GLFW_KEY_W => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.player_forward = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.player_forward = false;
            }
        },
        c.vulkan.GLFW_KEY_A => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.player_left = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.player_left = false;
            }
        },
        c.vulkan.GLFW_KEY_S => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.player_backwards = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.player_backwards = false;
            }
        },
        c.vulkan.GLFW_KEY_D => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.player_right = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.player_right = false;
            }
        },
        c.vulkan.GLFW_KEY_C => {
            if (action == c.vulkan.GLFW_PRESS) {
                input_state.toggle_free_cam = true;
            }
            if (action == c.vulkan.GLFW_RELEASE) {
                input_state.toggle_free_cam = false;
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
        c.vulkan.GLFW_KEY_T => { // DO NOT COPY THIS ONE IT DOES NOT TOGGLE THE KEY AS EXPECTED
            if (action == c.vulkan.GLFW_RELEASE) {
                if (input_state.mouse_capture == true) {
                    input_state.mouse_capture = false;
                } else {
                    input_state.mouse_capture = true;
                }
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
        input_state.mouse_dx += -dx;
        input_state.mouse_dy += -dy;
    }
}

pub export fn mouse_button_input_callback(
    window: ?*c.vulkan.GLFWwindow,
    button: i32,
    action: i32,
    mods: i32,
) void {
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
    // allocator: std.mem.Allocator,
    game_state: *GameState,
    obj: *Object,
    chunk_pos: @Vector(3, u32),
) !void {
    // for (0..(obj.size[0] * obj.size[1] * obj.size[2])) |chunk_index| {
    _ = &chunk_pos;
    const seed = game_state.seed;
    const data = try chunk.get_chunk_data_random(seed);
    const chunk_data = chunk.Chunk{
        .empty = false,
        .block_occupancy = undefined,
        .blocks = data,
    };
    try obj.chunks.put(chunk_pos, chunk_data);
    // }
}

/// .shape field in the BodyCreationSettings struct is overwritten.
fn add_body(
    game_state: *GameState,
    body_type: Type,
    half_size: @Vector(3, f32),
    settings: zphy.BodyCreationSettings,
) !UUID {
    const body_interface = game_state.physics_system.getBodyInterfaceMut();

    const shape_settings = try zphy.BoxShapeSettings.create(half_size);
    const shape = try shape_settings.asShapeSettings().createShape();
    var settings_with_shape = settings;
    settings_with_shape.shape = shape;
    const physics_id = try body_interface.createAndAddBody(
        settings_with_shape,
        .activate,
    );

    const result = UUID.init();
    try game_state.objects.put(result, .{
        .body_type = body_type,
        .physics_id = physics_id,
        .physics_settings = shape_settings.asShapeSettings(),
        .physics_shape = shape,
    });

    return result;
}

var test_chunk_uuid: UUID = undefined;

/// sandbox world template (plan for the survival world template)
fn sandbox_state_init(game_state: *GameState) !void {
    physics.clear_bodies(game_state.physics_system, game_state.objects.values());

    const body_interface = game_state.physics_system.getBodyInterfaceMut();

    {
        const cube_inertia = cm.calculate_cuboid_inertia_tensor(10.0, .{ 0.5, 1.0, 0.5 });

        // const player_shape_settings = try zphy.CapsuleShapeSettings.create(1.0, 0.5);
        const player_shape_settings = try zphy.BoxShapeSettings.create(.{ 0.5, 1.0, 0.5 });
        const player_shape = try player_shape_settings.asShapeSettings().createShape();
        const player_physics_id = try body_interface.createAndAddBody(
            .{
                .position = .{ 0.0, 10.0, 0.0, 1.0 },
                .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
                .shape = player_shape,
                .motion_type = .dynamic,
                .object_layer = physics.object_layers.moving,
                .gravity_factor = 0.0,
                .mass_properties_override = .{
                    .mass = 10.0,
                    .inertia = cube_inertia,
                },
            },
            .activate,
        );

        const player_UUID = UUID.init();
        try game_state.objects.put(player_UUID, .{
            .body_type = .player,
            .physics_id = player_physics_id,
            .physics_settings = player_shape_settings.asShapeSettings(),
            .physics_shape = player_shape,
        });
        game_state.playerUUID = player_UUID;
        game_state.playerPhysicsID = player_physics_id;
    }

    {
        const cube_inertia = cm.calculate_cuboid_inertia_tensor(1000.0, .{ 16.0, 16.0, 16.0 });

        // const player_shape_settings = try zphy.CapsuleShapeSettings.create(1.0, 0.5);
        const shape_settings = try zphy.BoxShapeSettings.create(.{ 16.0, 16.0, 16.0 });
        const shape = try shape_settings.asShapeSettings().createShape();
        const physics_id = try body_interface.createAndAddBody(
            .{
                .position = .{ 0.0, 30.0, 0.0, 1.0 },
                .rotation = .{ 0.0, 0.0, 1.0, 0.0 },
                .shape = shape,
                // .motion_type = .dynamic,
                // .object_layer = physics.object_layers.moving,
                .motion_type = .static,
                .object_layer = physics.object_layers.non_moving,
                // .gravity_factor = 1.0,
                .mass_properties_override = .{
                    .mass = 1000.0,
                    .inertia = cube_inertia,
                },
            },
            .activate,
        );

        const uuid = UUID.init();
        try game_state.objects.put(uuid, .{
            .body_type = .planet,
            .physics_id = physics_id,
            .physics_settings = shape_settings.asShapeSettings(),
            .physics_shape = shape,
            .chunks = std.AutoArrayHashMap(@Vector(3, u32), chunk.Chunk).init(game_state.allocator.*),
        });

        test_chunk_uuid = uuid;
    }

    _ = try add_body(
        game_state,
        .player,
        .{ 30.0, 1.0, 30.0 },
        .{
            .position = .{ -15.0, -1.0, -15.0, 1.0 },
            .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
            .shape = undefined,
            .motion_type = .static,
            .object_layer = physics.object_layers.non_moving,
            .gravity_factor = 0.0,
        },
    );

    _ = try add_body(
        game_state,
        .other,
        .{ 0.5, 0.5, 0.5 },
        .{
            .position = .{ 3.0, 0.0, 0.0, 1.0 },
            .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
            .shape = undefined,
            .motion_type = .dynamic,
            .object_layer = physics.object_layers.moving,
        },
    );

    _ = try add_body(
        game_state,
        .other,
        .{ 0.5, 0.5, 0.5 },
        .{
            .position = .{ -3.0, 0.0, 0.0, 1.0 },
            .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
            .shape = undefined,
            .motion_type = .dynamic,
            .object_layer = physics.object_layers.moving,
        },
    );

    _ = try add_body(
        game_state,
        .other,
        .{ 0.5, 0.5, 0.5 },
        .{
            .position = .{ -15.0, 0.0, 0.0, 1.0 },
            .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
            .shape = undefined,
            .motion_type = .dynamic,
            .object_layer = physics.object_layers.moving,
        },
    );

    _ = try add_body(
        game_state,
        .other,
        .{ 0.5, 0.5, 0.5 },
        .{
            .position = .{ -30.0, 10.0, 0.0, 1.0 },
            .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
            .shape = undefined,
            .motion_type = .dynamic,
            .object_layer = physics.object_layers.moving,
        },
    );

    game_state.logic_tick = true;
    game_state.logic_func = &sandbox_tick;
}

fn sandbox_tick(self: *GameState, delta_time: i64) void {
    _ = &delta_time;
    _ = &self;

    // std.debug.print("{}\n", .{delta_time});

    const body_interface = self.physics_system.getBodyInterfaceMut();

    // player controller
    if (input_state.toggle_free_cam) {
        input_state.toggle_free_cam = false;
        self.client_state.free_cam = !self.client_state.free_cam;
        const player_pos = body_interface.getPosition(self.playerPhysicsID);
        self.client_state.camera_pos = zm.loadArr3(player_pos);
    }

    if (self.client_state.free_cam) {
        const look = self.client_state.lookV();
        var input_vec: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 };
        const right = zm.cross3(look, .{ 0.0, 1.0, 0.0, 1.0 });

        if (input_state.jump) {
            input_vec += .{ 0.0, 1.0, 0.0, 1.0 };
        }
        if (input_state.crouch) {
            input_vec -= .{ 0.0, -1.0, 0.0, 1.0 };
        }
        if (input_state.player_forward) {
            input_vec += look;
        }
        if (input_state.player_backwards) {
            input_vec -= look;
        }
        if (input_state.player_right) {
            input_vec += right;
        }
        if (input_state.player_left) {
            input_vec -= right;
        }

        var speed: f32 = 0.025;

        if (input_state.sprint) {
            speed *= 4.0;
        }

        self.client_state.camera_pos += cm.scale_f32(input_vec, speed);
    } else {
        var input_vec: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 };

        const player_rot_matrix = zm.matFromQuat(@as(zm.Quat, body_interface.getRotation(self.playerPhysicsID)));
        const player_up = zm.mul(zm.Vec{ 0.0, -1.0, 0.0, 1.0 }, player_rot_matrix);
        const look = zm.mul(self.client_state.lookV(), player_rot_matrix);
        const right = zm.cross3(look, player_up);

        const feet_are_in_contact: bool = true;

        if (feet_are_in_contact and input_state.jump) {
            const jump_vec = cm.scale_f32(player_up, -3500.0);
            body_interface.addImpulse(self.playerPhysicsID, .{ jump_vec[0], jump_vec[1], jump_vec[2] });
            // input_vec += .{ 0.0, 1.0, 0.0, 0.0 };
        }
        if (feet_are_in_contact and input_state.crouch) {
            // TODO add crouching
            // input_vec += .{ 0.0, -1.0, 0.0, 0.0 };
        }
        if (input_state.player_forward) {
            // input_vec += .{ 0.0, 0.0, 1.0, 0.0 };
            input_vec += look;
        }
        if (input_state.player_backwards) {
            input_vec -= look;
        }
        if (input_state.player_right) {
            input_vec -= right;
        }
        if (input_state.player_left) {
            input_vec += right;
        }

        // const player_body_rot: zm.Vec = body_interface.getRotation(self.playerPhysicsID);
        // const player_move_dir = cm.mul_v_q(.{ 0, input_vec[0], input_vec[1], input_vec[2] }, player_body_rot);

        // std.debug.print("player move dir: {any}\n", .{player_move_dir});

        // std.debug.print("{}\n", .{input_vec});
        body_interface.addImpulse(self.playerPhysicsID, .{ input_vec[0] * 100.0, input_vec[1] * 100.0, input_vec[2] * 100.0 });
        // body_interface.setLinearVelocity(self.playerPhysicsID, .{ player_move_dir[1], player_move_dir[2], player_move_dir[3] });
    }

    const test_chunk_physics_id = self.objects.get(test_chunk_uuid).?.physics_id;

    // const delta_time_float: f32 = delta_time / 1000.0;
    const player_pos = zm.loadArr3(body_interface.getPosition(self.playerPhysicsID));
    const player_rot: zm.Quat = zm.loadArr4(body_interface.getRotation(self.playerPhysicsID));
    const test_chunk_pos = zm.loadArr3(body_interface.getPosition(test_chunk_physics_id));
    const distance = test_chunk_pos - player_pos;
    body_interface.addImpulse(self.playerPhysicsID, .{ distance[0] * 2.0, distance[1] * 2.0, distance[2] * 2.0 });

    const test_chunk_rot: zm.Quat = body_interface.getRotation(test_chunk_physics_id);
    const test_chunk_up = zm.mul(zm.Vec{ 0.0, 1.0, 0.0, 1.0 }, zm.matFromQuat(test_chunk_rot));
    const test_chunk_forward = zm.mul(zm.Vec{ 0.0, 0.0, 1.0, 1.0 }, zm.matFromQuat(test_chunk_rot));
    const test_chunk_right = zm.mul(zm.Vec{ 1.0, 0.0, 0.0, 1.0 }, zm.matFromQuat(test_chunk_rot));

    const player_chunk_up_dot = zm.dot3(test_chunk_up, zm.normalize3(distance));
    const player_chunk_forward_dot = zm.dot3(test_chunk_forward, zm.normalize3(distance));
    const player_chunk_right_dot = zm.dot3(test_chunk_right, zm.normalize3(distance));

    var best_dot = player_chunk_up_dot;
    var best_axis = test_chunk_up;
    if (@abs(player_chunk_forward_dot)[0] > @abs(best_dot)[0]) {
        best_dot = player_chunk_forward_dot;
        best_axis = test_chunk_forward;
    }
    if (@abs(player_chunk_right_dot)[0] > @abs(best_dot)[0]) {
        best_dot = player_chunk_right_dot;
        best_axis = test_chunk_right;
    }

    // const y_90 = zm.Quat{ 0.0, -0.71, 0.0, 0.71 };

    const lerp_c = 0.1;
    const ideal_dot_product = 0.5;
    if (@abs(best_dot[0]) > ideal_dot_product) {
        if (best_dot[0] < 0.0) { // if the dot is negative negate the rotation
            best_axis = -best_axis;
        }
        const target_rot = zm.qmul(test_chunk_rot, zm.Quat{ 0.0, 0.71, 0.0, -0.71 });
        // const test_chunk_down = zm.mul(zm.Vec{ 0.0, -1.0, 0.0, 1.0 }, zm.matFromQuat(test_chunk_rot));
        // target_rot = zm.qmul(target_rot, zm.Quat{ 0.0, 0.71, 0.0, 0.71 });
        std.debug.print("{} {} {} {}\n", .{ best_axis, target_rot, player_rot, best_dot[0] });

        // if (@abs(best_axis[1]) > 0.9) {
        //     std.debug.print("up\n", .{});
        // }
        // if (@abs(best_axis[0]) > 0.9) {
        //     std.debug.print("right\n", .{});
        // }
        // if (@abs(best_axis[2]) > 0.9) {
        //     std.debug.print("forward\n", .{});
        // }

        const rotation = cm.qnormalize(zm.slerp(player_rot, target_rot, lerp_c));
        body_interface.setRotation(self.playerPhysicsID, rotation, .activate);

        // body_interface.addAngularImpulse
    }

    // const target_orientation = zm.mul(.{ 0.0, 1.0, 0.0, 1.0 }, zm.matFromQuat(test_chunk_rot));
    // body_interface.addAngularImpulse(self.playerPhysicsID, .{  });

    // const sun_dir = cm.cast_position(self.objects.items[self.player_index].position - self.objects.items[self.sun_index].position);
    // const grav_dir = .{ 0.0, 1.0, 0.0, 0.0 }; // zm.normalize3(sun_dir);
    // const scale: f32 = 1.0 / zm.lengthSq3(sun_dir)[0] * physics.GRAVITATIONAL_CONSTANTf32 * 1.0 / self.objects.items[self.player_index].inverse_mass * 1.0 / self.objects.items[self.sun_index].inverse_mass;
    // const scale: f32 = -9.5;
    // const force = cm.scale_f32(grav_dir, -scale);
    // for (0..self.objects.items.len) |i| {
    //     if (self.objects.items[i].gravity) {
    //         self.objects.items[i].force_accumulation += force;
    //     }
    // }
}

// fn physics_test1_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
//     // player
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.0, -16.0 },
//         .inverse_mass = (1.0 / 100.0),
//         .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
//         .body_type = .player,
//     });
//     game_state.player_index = @intCast(game_state.objects.items.len - 1);

//     // Test1 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.0, 0.0 },
//         .inverse_mass = 1.0 / 1000.0,
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 1, 1, 1, 0.0 },
//         .body_type = .other,
//     });

//     // Test2 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 5.0, 0.0, 0.0 },
//         .inverse_mass = 1.0 / 1000.0,
//         .planet = false,
//         .velocity = .{ -1.0, 0.0, 0.0, 0.0 },
//         .gravity = false,
//         .half_size = .{ 1, 1, 1, 0.0 },
//         .body_type = .other,
//     });
// }

// fn physics_test2_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
//     // player
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.0, -16.0 },
//         .inverse_mass = (1.0 / 100.0),
//         .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
//         .body_type = .player,
//     });
//     game_state.player_index = @intCast(game_state.objects.items.len - 1);

//     // Test1 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.0, 0.0 },
//         .inverse_mass = 1.0 / 1000.0,
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 1, 1, 1, 0.0 },
//         .body_type = .other,
//     });

//     // Test2 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 5.0, 0.0, 0.0 },
//         .inverse_mass = 1.0 / 1000.0,
//         .planet = false,
//         .velocity = .{ -5.0, 0.0, 0.0, 0.0 },
//         .gravity = false,
//         .half_size = .{ 1, 1, 1, 0.0 },
//         .body_type = .other,
//     });
// }

// fn physics_test3_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
//     // player
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.0, -16.0 },
//         .inverse_mass = (1.0 / 100.0),
//         .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
//         .body_type = .player,
//     });
//     game_state.player_index = @intCast(game_state.objects.items.len - 1);

//     // Test1 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.0, 0.0 },
//         .inverse_mass = 1.0 / 1000.0,
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 1, 1, 1, 0.0 },
//         .body_type = .other,
//     });

//     // Test2 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 5.0, 0.0, 0.0 },
//         .inverse_mass = 1.0 / 5.0,
//         .velocity = .{ -5.0, 0.0, 0.0, 0.0 },
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 0.125, 0.125, 0.125, 0.0 },
//         .body_type = .other,
//     });
// }

// // Newtons Cradle
// fn physics_test4_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
//     // player
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.0, -8.0 },
//         .inverse_mass = (1.0 / 100.0),
//         .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
//         .body_type = .player,
//     });
//     game_state.player_index = @intCast(game_state.objects.items.len - 1);

//     // Test1 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.0, 0.0 },
//         .inverse_mass = 1.0 / 5.0,
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
//         .body_type = .other,
//     });

//     // Test2 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 1.0, 0.0, 0.0 },
//         .inverse_mass = 1.0 / 5.0,
//         .velocity = .{ 0.0, 0.0, 0.0, 0.0 },
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
//         .body_type = .other,
//     });

//     // Test3 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 3.0, 0.0, 0.0 },
//         .inverse_mass = 1.0 / 5.0,
//         .velocity = .{ -6.0, 0.0, 0.0, 0.0 },
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
//         .body_type = .other,
//     });
// }

// // Bernoulli's Problem
// fn physics_test5_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
//     // player
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.0, -8.0 },
//         .inverse_mass = (1.0 / 100.0),
//         .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
//         .body_type = .player,
//     });
//     game_state.player_index = @intCast(game_state.objects.items.len - 1);

//     // Test1 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, -0.5, 0.0 },
//         .inverse_mass = 1.0 / 5.0,
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
//         .body_type = .other,
//     });

//     // Test2 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.5, 0.0 },
//         .inverse_mass = 1.0 / 5.0,
//         .velocity = .{ 0.0, 0.0, 0.0, 0.0 },
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
//         .body_type = .other,
//     });

//     // Test3 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 4.0, 0.0, 0.0 },
//         .inverse_mass = 1.0 / 5.0,
//         .velocity = .{ -6.0, 0.0, 0.0, 0.0 },
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
//         .body_type = .other,
//     });
// }

// // multi point contact manifold generation test
// fn physics_test6_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
//     // player
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.0, -4.0 },
//         .inverse_mass = (1.0 / 100.0),
//         .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
//         .body_type = .player,
//     });
//     game_state.player_index = @intCast(game_state.objects.items.len - 1);

//     // Test1 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, -0.5, 0.0 },
//         .inverse_mass = 1.0 / 5.0,
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
//         .body_type = .other,
//         .lock_pos = true,
//         .lock_rot = true,
//     });

//     // Test2 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.5, 0.0 },
//         .inverse_mass = 1.0 / 5.0,
//         .velocity = .{ 0.0, 0.0, 0.0, 0.0 },
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
//         .body_type = .other,
//         .lock_pos = true,
//         .lock_rot = true,
//     });
// }

// // multi point contact manifold generation test
// fn physics_test7_game_state(game_state: *GameState, allocator: *std.mem.Allocator) !void {
//     // player
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.0, -4.0 },
//         .inverse_mass = (1.0 / 100.0),
//         .half_size = .{ 0.5, 1.0, 0.5, 0.0 },
//         .body_type = .player,
//     });
//     game_state.player_index = @intCast(game_state.objects.items.len - 1);

//     // Test1 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, -0.5, 0.0 },
//         .inverse_mass = 1.0 / 5.0,
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
//         .body_type = .other,
//         .lock_pos = true,
//         .lock_rot = true,
//     });

//     // Test2 Box
//     try game_state.objects.append(allocator.*, .{
//         .uuid = UUID.init(),
//         .position = .{ 0.0, 0.5, 0.0 },
//         .inverse_mass = 1.0 / 5.0,
//         .orientation = .{ 0.0, 0.5, 0.0, 0.87 },
//         .velocity = .{ 0.0, 0.0, 0.0, 0.0 },
//         .planet = false,
//         .gravity = false,
//         .half_size = .{ 0.5, 0.5, 0.5, 0.0 },
//         .body_type = .other,
//         .lock_pos = true,
//         .lock_rot = true,
//     });
// }

const ChunkInfo = struct { body_id: UUID, chunk_pos: @Vector(3, u32) };

fn check_chunks_to_load(
    objects: std.AutoArrayHashMap(UUID, Object),
    camera_pos: zm.Vec,
    physics_system: *zphy.PhysicsSystem,
    chunks: []ChunkInfo,
) void {
    _ = &camera_pos;
    _ = &chunks;
    const body_interface = physics_system.getBodyInterfaceMutNoLock();

    for (objects.keys(), objects.values()) |key, value| {
        _ = &key;
        const pos = body_interface.getPosition(value.physics_id);
        _ = &pos;
        // if () {}
    }
}

fn load_game_state(
    engine_state: *EngineState,
    new_game_state: *GameState,
) !void {
    // var start_load_time = std.time.milliTimestamp();

    engine_state.world_state = new_game_state;

    var chunks: [500]ChunkInfo = undefined;
    _ = &chunks;

    check_chunks_to_load(
        engine_state.world_state.objects,
        engine_state.world_state.client_state.camera_pos,
        engine_state.world_state.physics_system,
        @as([]ChunkInfo, @ptrCast(&chunks)),
    );

    // for (chunks) |chunk_data| {
    //     try load_chunk(
    //         engine_state.world_state,
    //         engine_state.world_state.objects.getPtr(chunk_data.body_id).?,
    //         chunk_data.chunk_pos,
    //     );
    // }

    // std.debug.print("[Debug] Loading chunks {}ms\n", .{std.time.milliTimestamp() - start_load_time});

    // start_load_time = std.time.milliTimestamp();

    // var chunk_count: i32 = 0;
    // for (engine_state.world_state.*.objects.items) |object| {
    //     if (object.body_type == .voxel_space) {
    //         for (0..object.chunks.items.len) |chunk_index| {
    //             const start_chunk_mesh_time = std.time.milliTimestamp();

    //             const chunk_mesh = try mesh_generation.CullMesh(
    //                 &object.chunks.items[chunk_index].blocks,
    //                 engine_state.allocator,
    //             );
    //             object.chunks.items[chunk_index].vertex_buffer = try vulkan.VulkanState.create_vertex_buffer(
    //                 engine_state.vulkan_state,
    //                 @sizeOf(vulkan.ChunkVertex),
    //                 @intCast(chunk_mesh.len * @sizeOf(vulkan.ChunkVertex)),
    //                 &chunk_mesh[0],
    //             );
    //             chunk_count += 1;
    //             engine_state.allocator.free(chunk_mesh);

    //             std.debug.print("chunk_index: {} | chunk mesh time: {}ms | chunk count: {}\n", .{
    //                 chunk_index,
    //                 std.time.milliTimestamp() - start_chunk_mesh_time,
    //                 chunk_count,
    //             });
    //         }
    //     }
    // }
    // std.debug.print("[Debug] Generating chunk meshes {}ms\n", .{std.time.milliTimestamp() - start_load_time});
}

fn unload_game_state(
    engine_state: *EngineState,
) void {
    engine_state.world_state.logic_tick = false;

    // for (0..engine_state.world_state.objects.items.len) |object_index| {
    //     const object: *Object = &engine_state.world_state.objects.items[object_index];
    //     if (object.body_type == .voxel_space) {
    //         object.chunks.deinit(engine_state.world_state.allocator.*);
    //     }
    // }
}
