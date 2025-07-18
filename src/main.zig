//Proceeds to zig all over the place...
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");
const zm = @import("zmath");
const mesh_generation = @import("mesh_generation.zig");
const chunk = @import("chunk.zig");
const physics = @import("physics.zig");

const ENGINE_NAME = "CeresVoxel";

var xpos: f64 = 0.0;
var ypos: f64 = 0.0;
var dx: f64 = 0.0;
var dy: f64 = 0.0;

// TODO There has got to be a better way than this, so much smell...
const chunk_vert_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/simple.vert.spv")))));
const chunk_frag_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/simple.frag.spv")))));

const outline_vert_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/outline.vert.spv")))));
const outline_frag_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/outline.frag.spv")))));

const cursor_vert_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/cursor.vert.spv")))));
const cursor_frag_source = @as([]align(4) u8, @constCast(@alignCast(@ptrCast(@embedFile("shaders/cursor.frag.spv")))));

const Inputs = packed struct {
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
};

var inputs = Inputs{};

const PlayerState = struct {
    pos: @Vector(3, f64) = .{ 0.0, 0.0, -1.0 },
    yaw: f32 = std.math.pi/2.0,
    pitch: f32 = 0.0,
    rot: zm.Quat = zm.qidentity(),
    up: zm.Vec = .{ 0.0, -1.0, 0.0, 1.0},
    speed: u32 = 5,
};

var player_state = PlayerState{};

const MAX_CONCURRENT_FRAMES = 2;

const block_selection_cube: [17]vulkan.Vertex = .{
    //front
    .{.pos = .{-0.001,-0.001,-0.001}, .color = .{1.0,1.0,1.0} },
    .{.pos = .{1.001,-0.001,-0.001}, .color = .{1.0,1.0,1.0} },
    .{.pos = .{1.001,1.001,-0.001}, .color = .{1.0,1.0,1.0} },
    .{.pos = .{-0.001,1.001,-0.001}, .color = .{1.0,1.0,1.0} },
    //left
    .{.pos = .{-0.001,-0.001,-0.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,-0.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,1.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,1.001,-0.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,-0.001,-0.001}, .color = .{1.0,1.0,1.0}},
    //right
    .{.pos = .{1.001,-0.001,-0.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{1.001,-0.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{1.001,1.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{1.001,1.001,-0.001}, .color = .{1.0,1.0,1.0}},
    //back
    .{.pos = .{1.001,1.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,1.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{-0.001,-0.001,1.001}, .color = .{1.0,1.0,1.0}},
    .{.pos = .{1.001,-0.001,1.001}, .color = .{1.0,1.0,1.0}},
};

const cursor_vertices: [6]vulkan.Vertex = .{
    .{.pos = .{-0.03125,-0.03125,0.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.03125,0.03125,0.0}, .color = .{1.0,1.0,0.0}},
    .{.pos = .{-0.03125,0.03125,0.0}, .color = .{0.0,1.0,0.0}},
    .{.pos = .{-0.03125,-0.03125,0.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.03125,-0.03125,0.0}, .color = .{1.0,0.0,0.0}},
    .{.pos = .{0.03215,0.03125,0.0}, .color = .{1.0,1.0,0.0}},
};
// 0 to 32768 can fit in u15, but for the sake of making our lives easier we will use a u16
//var block_selection_index: u32 = 0;

const GameState = struct {
    voxel_spaces: []chunk.VoxelSpace = undefined,
    seed: u64 = 0,
};

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
    var instance = vulkan.Instance{
        .allocator = &allocator,
        .MAX_CONCURRENT_FRAMES = MAX_CONCURRENT_FRAMES,
        .PUSH_CONSTANT_SIZE = @sizeOf(zm.Mat) + @sizeOf(f32),
    };

    // TODO move input and character movement into physics thread 
    //var speed : f32 = 5;
    //if (inputs.control)
    //{
    //    speed = 100;
    //}
    //
    //if (inputs.space)
    //{
    //    player_state.pos -= .{ up[0] * frame_delta * speed, up[1] * frame_delta * speed, up[2] * frame_delta * speed };
    //}
    //if (inputs.shift)
    //{
    //    player_state.pos += .{ up[0] * frame_delta * speed, up[1] * frame_delta * speed, up[2] * frame_delta * speed };
    //}
    //if (inputs.a)
    //{
    //    player_state.pos += .{ right[0] * frame_delta * speed, right[1] * frame_delta * speed, right[2] * frame_delta * speed };
    //}
    //if (inputs.d)
    //{
    //    player_state.pos -= .{ right[0] * frame_delta * speed, right[1] * frame_delta * speed, right[2] * frame_delta * speed };
    //}
    //if (inputs.w)
    //{
    //    player_state.pos -= .{ forward[0] * frame_delta * speed, forward[1] * frame_delta * speed, forward[2] * frame_delta * speed };
    //}
    //if (inputs.s)
    //{
    //    player_state.pos += .{ forward[0] * frame_delta * speed, forward[1] * frame_delta * speed, forward[2] * frame_delta * speed };
    //}
    
    var game_state = GameState{
        .voxel_spaces = try instance.allocator.*.alloc(chunk.VoxelSpace, 2),
    };
    defer instance.allocator.*.free(game_state.voxel_spaces);

    for (0..game_state.voxel_spaces.len) |index| {
        game_state.voxel_spaces[index].size = .{1,1,1};
        game_state.voxel_spaces[index].pos = .{@as(f32, @floatFromInt(index * 2 + index)), 0.0, 0.0};
    }

    var done: bool = false;
    var render_thread = try std.Thread.spawn(.{}, renderer, .{&game_state, &instance, &done});
    defer render_thread.join();
    _ = &render_thread;

    while (!done) {
        std.time.sleep(1);
        //std.debug.print("main thread\n", .{});
    }

    // CLEANUP
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
        player_state.yaw += @as(f32, @floatCast(dx * std.math.pi / 180.0 * MOUSE_SENSITIVITY));
        player_state.pitch -= @as(f32, @floatCast(dy * std.math.pi / 180.0 * MOUSE_SENSITIVITY));
    }

    //player_state.yaw = zm.clamp(player_state.yaw, -std.math.pi, std.math.pi);
    //player_state.pitch = zm.clamp(player_state.pitch, -std.math.pi, std.math.pi);
}

pub fn mouse_button_input_callback(window: ?*c.GLFWwindow, button: i32, action: i32, mods: i32) callconv(.C) void {
    _ = &button;
    _ = &window;
    _ = &mods;
    _ = &action;

    switch (button) {
        c.GLFW_MOUSE_BUTTON_LEFT => {
            if (action == c.GLFW_PRESS) {
                inputs.left_click = true;
            }
            if (action == c.GLFW_RELEASE) {
                inputs.left_click = false;
            }
        },
        c.GLFW_MOUSE_BUTTON_RIGHT => {
            if (action == c.GLFW_PRESS) {
                inputs.right_click = true;
            }
            if (action == c.GLFW_RELEASE) {
                inputs.right_click = false;
            }
        },
        else => {},
    }
}

pub fn window_resize_callback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    _ = &width;
    _ = &height;
    const instance: *vulkan.Instance = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));
    instance.framebuffer_resized = true;
}

fn renderer(game_state: *GameState, instance: *vulkan.Instance, done: *bool) !void {
    instance.shader_modules = std.ArrayList(c.VkShaderModule).init(instance.allocator.*);
    defer instance.shader_modules.deinit();

    instance.pipelines = try instance.allocator.*.alloc(c.VkPipeline, 3);
    defer instance.allocator.*.free(instance.pipelines);

    instance.vertex_buffers = std.ArrayList(c.VkBuffer).init(instance.allocator.*);
    defer instance.vertex_buffers.deinit();
    instance.vertex_allocs = std.ArrayList(c.VmaAllocation).init(instance.allocator.*);
    defer instance.vertex_allocs.deinit();
    
    instance.render_targets = std.ArrayList(vulkan.RenderInfo).init(instance.allocator.*);
    defer instance.render_targets.deinit();

    instance.ubo_buffers = std.ArrayList(c.VkBuffer).init(instance.allocator.*);
    defer instance.ubo_buffers.deinit();
    instance.ubo_allocs = std.ArrayList(c.VmaAllocation).init(instance.allocator.*);
    defer instance.ubo_allocs.deinit();
    
    instance.ssbo_buffers = std.ArrayList(c.VkBuffer).init(instance.allocator.*);
    defer instance.ssbo_buffers.deinit();
    instance.ssbo_allocs = std.ArrayList(c.VmaAllocation).init(instance.allocator.*);
    defer instance.ssbo_allocs.deinit();

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
    
    const vma_allocator_success = c.vmaCreateAllocator(&vma_allocator_create_info, &instance.vma_allocator);

    if (vma_allocator_success != c.VK_SUCCESS)
    {
        std.debug.print("Unable to create vma allocator {}\n", .{vma_allocator_success});
    }

    try instance.create_depth_resources();

    instance.push_constant_info = c.VkPushConstantRange{
        .stageFlags = c.VK_SHADER_STAGE_ALL,
        .offset = 0,
        // must be a multiple of 4
        .size = instance.PUSH_CONSTANT_SIZE,
    };
    
    try instance.create_pipeline_layout();
try instance.create_render_pass();
    // cursor
    instance.pipelines[0] = try instance.create_generic_pipeline(cursor_vert_source, cursor_frag_source, false);
    // outline
    instance.pipelines[1] = try instance.create_outline_pipeline(outline_vert_source, outline_frag_source);
    // simple chunk
    instance.pipelines[2] = try instance.create_simple_chunk_pipeline(chunk_vert_source, chunk_frag_source, false);
    try instance.create_framebuffers();
    try instance.create_command_pool();
    try instance.create_command_buffers();
    try instance.create_sync_objects();

    // GLFW INIT
    _ = c.glfwSetKeyCallback(instance.window, key_callback);

    _ = c.glfwSetCursorPosCallback(instance.window, cursor_pos_callback);
    _ = c.glfwSetWindowUserPointer(instance.window, @constCast(instance));
    _ = c.glfwSetFramebufferSizeCallback(instance.window, window_resize_callback);
    _ = c.glfwSetMouseButtonCallback(instance.window, mouse_button_input_callback);

    c.glfwSetWindowSizeLimits(instance.window, 240, 135, c.GLFW_DONT_CARE, c.GLFW_DONT_CARE);

    // cursor
    try instance.render_targets.append(.{ .vertex_index = 0, .pipeline_index = 0});
    // outline
    try instance.render_targets.append(.{ .vertex_index = 1, .pipeline_index = 1});
    
    try instance.create_vertex_buffer(0, @sizeOf(vulkan.Vertex), @intCast(cursor_vertices.len * @sizeOf(vulkan.Vertex)), @ptrCast(@constCast(&cursor_vertices[0])));
    try instance.create_vertex_buffer(1, @sizeOf(vulkan.Vertex), @intCast(block_selection_cube.len * @sizeOf(vulkan.Vertex)), @ptrCast(@constCast(&block_selection_cube[0])));

    try instance.render_targets.ensureUnusedCapacity(game_state.voxel_spaces.len);
    
    const ChunkRenderData = struct {
        size: @Vector(3, u32),
        pos: @Vector(3, f32),
        model: zm.Mat = zm.identity(),
    };
    
    var chunk_render_data: std.ArrayList(ChunkRenderData) = std.ArrayList(ChunkRenderData).init(instance.allocator.*);
    defer chunk_render_data.deinit();

    var last_space_chunk_index: u32 = 0;
    // TODO add entries in a chunk data storage buffer for chunk pos etc.
    for (game_state.voxel_spaces, 0..game_state.voxel_spaces.len) |vs, space_index| {
        var mesh_data = std.ArrayList(vulkan.ChunkVertex).init(instance.allocator.*);
        defer mesh_data.deinit();

        for (0..vs.size[0] * vs.size[1] * vs.size[2]) |chunk_index| {
            // The goal is for this get chunk to be faster than reading the disk for an unmodified chunk
            const data = try chunk.get_chunk_data(game_state.seed, @intCast(space_index), .{0,0,0});
            const mesh_start: f64 = c.glfwGetTime();
            const new_vertices_count = try mesh_generation.cull_mesh(&data, @intCast(last_space_chunk_index + chunk_index), &mesh_data);
            std.debug.print("[Debug] time: {d:.4}ms \n", .{(c.glfwGetTime() - mesh_start) * 1000.0});
            _ = &new_vertices_count;
            std.debug.print("[Debug] vertice count: {}\n", .{new_vertices_count});

            try chunk_render_data.append(.{
                .model = zm.translation(@floatCast(vs.pos[0]), @floatCast(vs.pos[1]), @floatCast(vs.pos[2])),
                .size = vs.size,
                .pos = .{
                    @floatFromInt(chunk_index % vs.size[0] * 32),
                    @floatFromInt(chunk_index / vs.size[0] % vs.size[1] * 32),
                    @floatFromInt(chunk_index / vs.size[0] / vs.size[1] % vs.size[2] * 32),
                },
            });
        }
        last_space_chunk_index += vs.size[0] * vs.size[1] * vs.size[2];

        const render_index: u32 = 2 + @as(u32, @intCast(space_index));
        game_state.voxel_spaces[space_index].render_index = render_index;
        try instance.render_targets.append(.{ .vertex_index = render_index, .pipeline_index = 2, .vertex_render_offset = 0});
        try instance.create_vertex_buffer(render_index, @sizeOf(vulkan.ChunkVertex), @intCast(mesh_data.items.len * @sizeOf(vulkan.ChunkVertex)), mesh_data.items.ptr);
    }


    // TODO initialize chunk data appropriately
    try instance.create_ssbo(@intCast(chunk_render_data.items.len * @sizeOf(ChunkRenderData)), &chunk_render_data.items[0]);

    // RENDER INIT

    const BlockSelectorTransform = struct {
        model: zm.Mat = zm.identity(),
    };
    
    var selector_transform = BlockSelectorTransform{};

    const create_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = @sizeOf(BlockSelectorTransform),
        .usage = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
    };

    const ubo_alloc_create_info = c.VmaAllocationCreateInfo{
        .usage = c.VMA_MEMORY_USAGE_AUTO,
        .flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
    };

    for (0..instance.vertex_buffers.items.len*MAX_CONCURRENT_FRAMES) |i|
    {
        _ = &i;
         
        var buffer: c.VkBuffer = undefined;
        var alloc: c.VmaAllocation = undefined;
        _ = c.vmaCreateBuffer(instance.vma_allocator, &create_info, &ubo_alloc_create_info, &buffer, &alloc, null);
        
        _ = c.vmaCopyMemoryToAllocation(instance.vma_allocator, &selector_transform, alloc, 0, @sizeOf(BlockSelectorTransform));
        try instance.ubo_allocs.append(alloc);
        try instance.ubo_buffers.append(buffer);
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
    const image_data0 = c.stbi_load("fortnite.jpg", &image_info0.width, &image_info0.height, &image_info0.channels, c.STBI_rgb_alpha);
    if (image_data0 == null){
        std.debug.print("Unable to find image file \n", .{});
        return;
    }
    else
    {
        image_info0.data = image_data0;
    }

    try vulkan.create_2d_texture(instance, &image_info0);
    c.stbi_image_free(image_info0.data);

    try vulkan.create_image_view(instance.device, &image_info0);
    try vulkan.create_samplers(instance, &image_info0, c.VK_FILTER_LINEAR, c.VK_SAMPLER_ADDRESS_MODE_REPEAT, true);
    
    var image_info1 = vulkan.ImageInfo{
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
    defer instance.allocator.*.free(image_info1.views);
    defer instance.allocator.*.free(image_info1.samplers);
   
    // TODO turn this into a one line conditional
    const image_data1 = c.stbi_load("blocks.png", &image_info1.width, &image_info1.height, &image_info1.channels, c.STBI_rgb_alpha);
    if (image_data1 == null){
        std.debug.print("Unable to find image file \n", .{});
        return;
    }
    else
    {
        image_info1.data = image_data1;
    }

    try vulkan.create_2d_texture(instance, &image_info1);
    c.stbi_image_free(image_info1.data);

    try vulkan.create_image_view(instance.device, &image_info1);
    try vulkan.create_samplers(instance, &image_info1, c.VK_FILTER_NEAREST, c.VK_SAMPLER_ADDRESS_MODE_REPEAT, false);

    // Descriptor Sets
    
    const layouts: [2]c.VkDescriptorSetLayout = .{instance.descriptor_set_layout, instance.descriptor_set_layout};
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
        const buffers: [2]c.VkDescriptorBufferInfo = .{
            c.VkDescriptorBufferInfo{
                .buffer = instance.ubo_buffers.items[i],
                .offset = 0,
                .range = @sizeOf(BlockSelectorTransform),
            },
            c.VkDescriptorBufferInfo{
                .buffer = instance.ssbo_buffers.items[0],
                .offset = 0,
                .range = chunk_render_data.items.len * @sizeOf(ChunkRenderData),
            },
        };
        
        const images: [2]c.VkDescriptorImageInfo = .{
            c.VkDescriptorImageInfo{
                .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                .imageView = image_info0.views[i],
                .sampler = image_info0.samplers[i],
            },
            c.VkDescriptorImageInfo{
                .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                .imageView = image_info1.views[i],
                .sampler = image_info1.samplers[i],
            }
        };

        const descriptor_writes: [4]c.VkWriteDescriptorSet = .{
            c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = instance.descriptor_sets[i],
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = 1,
                .pBufferInfo = &buffers[0],
                .pImageInfo = null,
                .pTexelBufferView = null,
            },
            c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = instance.descriptor_sets[i],
                .dstBinding = 1,
                .dstArrayElement = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .pBufferInfo = null,
                .pImageInfo = &images[0],
                .pTexelBufferView = null,
            },
            c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = instance.descriptor_sets[i],
                .dstBinding = 2,
                .dstArrayElement = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = 1,
                .pBufferInfo = null,
                .pImageInfo = &images[1],
                .pTexelBufferView = null,
            },
            c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = instance.descriptor_sets[i],
                .dstBinding = 3,
                .dstArrayElement = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount = 1,
                .pBufferInfo = &buffers[1],
                .pImageInfo = null,
                .pTexelBufferView = null,
            },
        };

        c.vkUpdateDescriptorSets(instance.device, descriptor_writes.len, &descriptor_writes, 0, null);
    }

    instance.push_constant_data = try instance.allocator.*.alloc(u8, instance.PUSH_CONSTANT_SIZE);
    defer instance.allocator.*.free(instance.push_constant_data);

    var frame_count: u64 = 0;
    var current_frame_index: u32 = 0;
    var previous_frame_time: f32 = 0.0;

    var window_height : i32 = 0;
    var window_width : i32 = 0;

    var frame_time_buffer_index: u32 = 0;
    var frame_time_cyclic_buffer: [256]f32 = undefined;
    // TODO replace this with splat?
    @memset(&frame_time_cyclic_buffer, 0.0);

    while (c.glfwWindowShouldClose(instance.window) == 0) {
        const current_time : f32 = @floatCast(c.glfwGetTime());
        const frame_delta: f32 = current_time - previous_frame_time;
        previous_frame_time = current_time;
        
        c.glfwPollEvents();

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

        const look = zm.normalize3(@Vector(4, f32){
            @as(f32, @floatCast(std.math.cos(player_state.yaw) * std.math.cos(player_state.pitch))),
            @as(f32, @floatCast(std.math.sin(player_state.pitch))),
            @as(f32, @floatCast(std.math.sin(player_state.yaw) * std.math.cos(player_state.pitch))),
            0.0,
        });
        const up : zm.Vec = player_state.up;
        //const right = zm.cross3(look, up);
        //const forward = zm.cross3(right, up);

        const view: zm.Mat = zm.lookToLh(.{@floatCast(player_state.pos[0]), @floatCast(player_state.pos[1]), @floatCast(player_state.pos[2]), 0.0}, look, up);
        const projection: zm.Mat = zm.perspectiveFovLh(1.0, aspect_ratio, 0.1, 1000.0);
        const view_proj: zm.Mat = zm.mul(view, projection);
        
        var average_frame_time: f32 = 0;
        for (frame_time_cyclic_buffer) |time|
        {
            average_frame_time += time;
        }
        average_frame_time /= 256;

        std.debug.print("\t{s} pos:{d:.1} {d:.1} {d:.1} y:{d:.1} p:{d:.1} {d:.3}ms\r", .{
            if (inputs.mouse_capture) "on " else "off",
            player_state.pos[0], 
            player_state.pos[1],
            player_state.pos[2],
            player_state.yaw,
            player_state.pitch,
            average_frame_time * 1000.0,
        });

        frame_time_cyclic_buffer[frame_time_buffer_index] = frame_delta;
        if (frame_time_buffer_index < 255) {
            frame_time_buffer_index += 1;
        } else {
            frame_time_buffer_index = 0;
        }
        
        @memcpy(instance.push_constant_data[0..64], @as([]u8, @ptrCast(@constCast(&view_proj)))[0..64]);
        @memcpy(instance.push_constant_data[@sizeOf(zm.Mat)..(@sizeOf(zm.Mat) + 4)], @as([*]u8, @ptrCast(@constCast(&aspect_ratio)))[0..4]);

        for (game_state.voxel_spaces) |space| {
            instance.render_targets.items[space.render_index].rendering_enabled = distance_test(&player_state.pos, &space.pos, 200.0);
        }

        //_ = c.vmaCopyMemoryToAllocation(instance.vma_allocator, &selector_transform, instance.ubo_allocs.items[current_frame_index], 0, @sizeOf(BlockSelectorTransform));

        try instance.draw_frame(current_frame_index);

        current_frame_index = (current_frame_index + 1) % instance.MAX_CONCURRENT_FRAMES;
        frame_count += 1;
    }
    
    _ = c.vkDeviceWaitIdle(instance.device);
    
    vulkan.image_cleanup(instance, &image_info0);
    vulkan.image_cleanup(instance, &image_info1);
    instance.cleanup();
    
    done.* = true;
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
