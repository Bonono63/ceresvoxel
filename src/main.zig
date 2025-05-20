//Proceeds to zig all over the place...
const std = @import("std");
const c = @import("clibs.zig");
const vulkan = @import("vulkan.zig");
const zm = @import("zmath");
const meshers = @import("mesh_generation.zig");

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
    mouse_capture : bool = true
};

var inputs = Inputs{};

const PlayerState = struct {
    pos: @Vector(3, f32) = .{ 0.0, 0.0, -1.0 },
    yaw: f32 = std.math.pi/2.0,
    pitch: f32 = 0.0,
    rot: zm.Quat = zm.qidentity(),
    up: zm.Vec = .{ 0.0, -1.0, 0.0, 1.0},
    look: zm.Vec = .{ 0.0, 0.0, 1.0, 1.0 },
};

const PhysicsEntity = struct {
    pos: @Vector(3, f32) = .{0.0,0.0,0.0},
};

var player_state = PlayerState{};

const MAX_CONCURRENT_FRAMES = 2;

const block_selection_cube: [17]vulkan.Vertex = .{
    //front
    .{.pos = .{0.0,0.0,0.0}, .color = .{0.0,0.0,0.0} },
    .{.pos = .{1.0,0.0,0.0}, .color = .{0.0,0.0,0.0} },
    .{.pos = .{1.0,1.0,0.0}, .color = .{0.0,0.0,0.0} },
    .{.pos = .{0.0,1.0,0.0}, .color = .{0.0,0.0,0.0} },
    //left
    .{.pos = .{0.0,0.0,0.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.0,0.0,1.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.0,1.0,1.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.0,1.0,0.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.0,0.0,0.0}, .color = .{0.0,0.0,0.0}},
    //right
    .{.pos = .{1.0,0.0,0.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{1.0,0.0,1.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{1.0,1.0,1.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{1.0,1.0,0.0}, .color = .{0.0,0.0,0.0}},
    //back
    .{.pos = .{1.0,1.0,1.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.0,1.0,1.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.0,0.0,1.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{1.0,0.0,1.0}, .color = .{0.0,0.0,0.0}},
};

const cursor_vertices: [6]vulkan.Vertex = .{
    .{.pos = .{-0.0625,-0.0625,0.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.0625,0.0625,0.0}, .color = .{1.0,1.0,0.0}},
    .{.pos = .{-0.0625,0.0625,0.0}, .color = .{0.0,1.0,0.0}},
    .{.pos = .{-0.0625,-0.0625,0.0}, .color = .{0.0,0.0,0.0}},
    .{.pos = .{0.0625,-0.0625,0.0}, .color = .{1.0,0.0,0.0}},
    .{.pos = .{0.0625,0.0625,0.0}, .color = .{1.0,1.0,0.0}},
};
// 0 to 32768 can fit in u15, but for the sake of making our lives easier we will use a u16
var block_selection_index: u32 = 0;

fn pos_to_index(pos: @Vector(3, f32)) u16 {
    return pos[0] + pos[1] * 32 + pos[2] * 32 * 32;
}

//fn index_to_pos(index: u16) @Vector(3,f32) {
//    return .{index % 32, index / 32 % 32, index / 32 / 32 % 32};
//}

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
    var instance = vulkan.Instance{ .allocator = &allocator, .MAX_CONCURRENT_FRAMES = MAX_CONCURRENT_FRAMES };

    instance.shader_modules = std.ArrayList(c.VkShaderModule).init(instance.allocator.*);
    defer instance.shader_modules.deinit();

    instance.pipelines = try instance.allocator.*.alloc(c.VkPipeline, 3);
    defer instance.allocator.*.free(instance.pipelines);

    instance.vertex_buffers = std.ArrayList(c.VkBuffer).init(instance.allocator.*);
    defer instance.vertex_buffers.deinit();
    instance.vertex_allocs = std.ArrayList(c.VmaAllocation).init(instance.allocator.*);
    defer instance.vertex_allocs.deinit();
    instance.vertex_offsets = std.ArrayList(c.VkDeviceSize).init(instance.allocator.*);
    defer instance.vertex_offsets.deinit();
    instance.vertex_counts = std.ArrayList(u32).init(instance.allocator.*);
    defer instance.vertex_counts.deinit();

    instance.ubo_buffers = std.ArrayList(c.VkBuffer).init(instance.allocator.*);
    defer instance.ubo_buffers.deinit();
    instance.ubo_allocs = std.ArrayList(c.VmaAllocation).init(instance.allocator.*);
    defer instance.ubo_allocs.deinit();


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

    const PUSH_CONSTANT_COUNT = 1;
    instance.push_constant_info = try instance.allocator.*.alloc(c.VkPushConstantRange, PUSH_CONSTANT_COUNT);
    defer instance.allocator.*.free(instance.push_constant_info);
    instance.push_constant_data = try instance.allocator.*.alloc(*anyopaque, PUSH_CONSTANT_COUNT);
    defer instance.allocator.*.free(instance.push_constant_data);

    const PUSH_CONSTANT_SIZE: u32 = @sizeOf(zm.Mat) + 4 + 4;
    // Push constant layout is 64 bytes: view_proj | 4 bytes: block_selection_index | 4 bytes: aspect ratio
    instance.push_constant_info[0] = c.VkPushConstantRange{
        .stageFlags = c.VK_SHADER_STAGE_ALL,
        .offset = 0,
        // must be a multiple of 4
        .size = PUSH_CONSTANT_SIZE,
    };

    //instance.push_constant_info[1] = c.VkPushConstantRange{
    //    .stageFlags = c.VK_SHADER_STAGE_ALL,
    //    .offset = @sizeOf(zm.Mat),
    //    // must be a multiple of 4
    //    .size = @sizeOf(u32),
    //};
    
    try instance.create_pipeline_layout();
    try instance.create_render_pass();
    instance.pipelines[0] = try instance.create_generic_pipeline(chunk_vert_source, chunk_frag_source, false);
    instance.pipelines[1] = try instance.create_outline_pipeline(outline_vert_source, outline_frag_source);
    instance.pipelines[2] = try instance.create_generic_pipeline(cursor_vert_source, cursor_frag_source, false);
    try instance.create_framebuffers();
    try instance.create_command_pool();
    try instance.create_command_buffers();
    try instance.create_sync_objects();

    // GLFW INIT
    _ = c.glfwSetKeyCallback(instance.window, key_callback);

    _ = c.glfwSetCursorPosCallback(instance.window, cursor_pos_callback);
    _ = c.glfwSetWindowUserPointer(instance.window, &instance);
    _ = c.glfwSetFramebufferSizeCallback(instance.window, window_resize_callback);

    c.glfwSetWindowSizeLimits(instance.window, 240, 135, c.GLFW_DONT_CARE, c.GLFW_DONT_CARE);

    const random = std.crypto.random; 

    var chunk_data : [32768]u8 = undefined;
    for (0..32768) |i|
    {
        const val = random.int(u1);
        chunk_data[i] = val;
    }

    const chunk_mesh_start_time : f64 = c.glfwGetTime();
    const chunk_vertices : std.ArrayList(vulkan.Vertex) = try meshers.basic_mesh(instance.allocator, &chunk_data);
    defer chunk_vertices.deinit();

    std.debug.print("chunk mesh time: {d:.3}ms\n", .{ (c.glfwGetTime() - chunk_mesh_start_time) * 1000.0 });
    
    try instance.create_vertex_buffer(@intCast(chunk_vertices.items.len * @sizeOf(vulkan.Vertex)), chunk_vertices.items.ptr);
    try instance.create_vertex_buffer(@intCast(block_selection_cube.len * @sizeOf(vulkan.Vertex)), @ptrCast(@constCast(&block_selection_cube[0])));
    try instance.create_vertex_buffer(@intCast(cursor_vertices.len * @sizeOf(vulkan.Vertex)), @ptrCast(@constCast(&cursor_vertices[0])));

    // RENDER INIT

    const ObjectTransform = struct {
        model: zm.Mat = zm.identity(),
        view: zm.Mat = zm.identity(),
        projection: zm.Mat = zm.identity(),
    };
    
    var object_transform = ObjectTransform{};
    
    const create_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = @sizeOf(ObjectTransform),
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
        
        _ = c.vmaCopyMemoryToAllocation(instance.vma_allocator, &object_transform, alloc, 0, @sizeOf(ObjectTransform));
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
    const image_data = c.stbi_load("fortnite.jpg", &image_info0.width, &image_info0.height, &image_info0.channels, c.STBI_rgb_alpha);
    if (image_data == null){
        std.debug.print("Unable to find image file \n", .{});
        return;
    }
    else
    {
        image_info0.data = image_data;
    }

    try vulkan.create_2d_texture(&instance, &image_info0);
    c.stbi_image_free(image_info0.data);

    try vulkan.create_image_view(instance.device, &image_info0);
    try vulkan.create_samplers(&instance, &image_info0, c.VK_FILTER_LINEAR, c.VK_SAMPLER_ADDRESS_MODE_REPEAT);

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
        const buffer_info = c.VkDescriptorBufferInfo{
            .buffer = instance.ubo_buffers.items[i],
            .offset = 0,
            .range = @sizeOf(ObjectTransform),
        };
        
        const image_info = c.VkDescriptorImageInfo{
            .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = image_info0.views[i],
            .sampler = image_info0.samplers[i],
        };

        const ubo_descriptor_write = c.VkWriteDescriptorSet{
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
        
        const image_descriptor_write = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = instance.descriptor_sets[i],
            .dstBinding = 1,
            .dstArrayElement = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .pBufferInfo = null,
            .pImageInfo = &image_info,
            .pTexelBufferView = null,
        };

        const descriptor_writes: [2]c.VkWriteDescriptorSet = .{ubo_descriptor_write, image_descriptor_write};

        c.vkUpdateDescriptorSets(instance.device, descriptor_writes.len, &descriptor_writes, 0, null);
    }

    // FRAME LOOP

    var frame_count: u64 = 0;
    var current_frame_index: u32 = 0;
    var previous_frame_time: f32 = 0.0;

    var window_height : i32 = 0;
    var window_width : i32 = 0;
    
    var push_data: [PUSH_CONSTANT_SIZE]u8 = undefined;
    instance.push_constant_data[0] = @as(*anyopaque, @ptrCast(@constCast(&push_data)));
    
    while (c.glfwWindowShouldClose(instance.window) == 0) {
        c.glfwPollEvents();

        const current_time : f32 = @floatCast(c.glfwGetTime());
        const frame_delta: f32 = current_time - previous_frame_time;
        previous_frame_time = current_time;

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

        player_state.look[0] = @as(f32, @floatCast(std.math.cos(player_state.yaw) * std.math.cos(player_state.pitch)));
        player_state.look[1] = @as(f32, @floatCast(std.math.sin(player_state.pitch)));
        player_state.look[2] = @as(f32, @floatCast(std.math.sin(player_state.yaw) * std.math.cos(player_state.pitch)));
        std.debug.print("{} \n", .{player_state.look});
        const look = zm.normalize3(player_state.look);
        //const test_gravity: @Vector(3, f32) = .{0.0,3.0,0.0};
        //const gravity_dir_vec = player_state.pos - test_gravity;
        //const up : zm.Vec = zm.normalize3(.{-gravity_dir_vec[0],-gravity_dir_vec[1],-gravity_dir_vec[2], 1.0});
        const up : zm.Vec = .{0.0,-1.0,0.0,1.0};
        const right = zm.cross3(look, up);
        const forward = zm.cross3(right, up);

        const view: zm.Mat = zm.lookToLh(.{player_state.pos[0], player_state.pos[1], player_state.pos[2], 1.0}, look, up);
        const projection: zm.Mat = zm.perspectiveFovLh(1.0, aspect_ratio, 0.1, 1000.0);
        object_transform.view = zm.mul(object_transform.view, object_transform.projection);

        const view_proj: zm.Mat = zm.mul(view, projection);
        
        const index: u32 = camera_block_intersection(&chunk_data, .{0.0,0.0,0.0,0.0}, player_state.look, player_state.pos);
        @memcpy(push_data[0..64], @as([]u8, @ptrCast(@constCast(&view_proj)))[0..64]);
        @memcpy(push_data[@sizeOf(zm.Mat)..(@sizeOf(zm.Mat) + 4)], @as([*]u8, @ptrCast(@constCast(&index)))[0..4]);
        @memcpy(push_data[(@sizeOf(zm.Mat) + 4)..(@sizeOf(zm.Mat) + 4 + 4)], @as([*]u8, @ptrCast(@constCast(&aspect_ratio)))[0..4]);

        var speed : f32 = 5;
        if (inputs.control)
        {
            speed = 10;
        }

        // TODO Make this the center of gravitational wells and such
        if (inputs.space)
        {
            player_state.pos -= .{ up[0] * frame_delta * speed, up[1] * frame_delta * speed, up[2] * frame_delta * speed };
        }
        if (inputs.shift)
        {
            player_state.pos += .{ up[0] * frame_delta * speed, up[1] * frame_delta * speed, up[2] * frame_delta * speed };
        }
        if (inputs.a)
        {
            player_state.pos += .{ right[0] * frame_delta * speed, right[1] * frame_delta * speed, right[2] * frame_delta * speed };
        }
        if (inputs.d)
        {
            player_state.pos -= .{ right[0] * frame_delta * speed, right[1] * frame_delta * speed, right[2] * frame_delta * speed };
        }
        if (inputs.w)
        {
            player_state.pos -= .{ forward[0] * frame_delta * speed, forward[1] * frame_delta * speed, forward[2] * frame_delta * speed };
        }
        if (inputs.s)
        {
            player_state.pos += .{ forward[0] * frame_delta * speed, forward[1] * frame_delta * speed, forward[2] * frame_delta * speed };
        }

        std.debug.print("\t{s} pos:{d:.1} {d:.1} {d:.1} y:{d:.1} p:{d:.1} {d:.3}ms \r", .{
            if (inputs.mouse_capture) "on " else "off",
            player_state.pos[0], 
            player_state.pos[1],
            player_state.pos[2],
            player_state.yaw,
            player_state.pitch,
            frame_delta * 1000.0,
        });

        //_ = c.vmaCopyMemoryToAllocation(instance.vma_allocator, &object_transform, instance.ubo_allocs.items[current_frame_index], 0, @sizeOf(ObjectTransform));

        try instance.draw_frame(current_frame_index);

        current_frame_index = (current_frame_index + 1) % instance.MAX_CONCURRENT_FRAMES;
        frame_count += 1;
    }

    // CLEANUP

    _ = c.vkDeviceWaitIdle(instance.device);

    vulkan.image_cleanup(&instance, &image_info0);
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

pub fn window_resize_callback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    _ = &width;
    _ = &height;
    const instance: *vulkan.Instance = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));
    instance.framebuffer_resized = true;
}

fn camera_block_intersection(chunk_data: *[32768]u8, chunk_pos: zm.Vec, look: zm.Vec, origin: @Vector(3, f32)) u32
{
    _ = &chunk_data;
    _ = &look;
    _ = &origin;
    _ = &chunk_pos;

    var result: u32 = 0;

    const max_steps: u32 = 10;
    var steps: u32 = 0;
    //TODO do a chunk bounds test

    const ratio = look;
    std.debug.print("l: {} nl:{} r: {}\n", .{look, zm.normalize3(look), ratio});

    const origin_adjustment: @Vector(4,f32) = .{origin[0], origin[1], origin[2], 1.0};
    var current_ray: zm.Vec = zm.normalize3(origin_adjustment) + look;
    // TODO eventually shift to OBB instead of AABB test, but rotations aren't implemented so we can ignore that for now
    var current_length: @Vector(4, f32) = zm.length3(current_ray);
    std.debug.print("{d:.2} {d:.2} {d:.2}  {d:.2} {d:.2} {d:.2} {d:.2} {d:.2} {d:.2}\n", .{current_length[0], current_length[1], current_length[2], origin[0], origin[1], origin[2], current_ray[0], current_ray[1], current_ray[2]});
    while (((current_ray[0] < chunk_pos[0] or current_ray[0] > chunk_pos[0] + 31.0) or (current_ray[2] < chunk_pos[2] or current_ray[2] > chunk_pos[2] + 31.0)) and !(steps == max_steps))
    {
        std.debug.print("current ray not within chunk bounds {} {} {}\n", .{current_ray, ratio, current_length});
        // X test
        if (current_length[0] < current_length[1] and current_length[0] < current_length[2]) {
            current_ray[0] += ratio[0];
        }
        //// Y test
        //if (current_length[1] < current_length[0] and current_length[1] < current_length[2]) {
        //    current_ray[1] += ratio[1];
        //}
        //// Z test
        if (current_length[2] < current_length[0] and current_length[2] < current_length[1]) {
            current_ray[2] += ratio[2];
        }
        current_length = zm.length3(current_ray);
        steps += 1;
    }

    std.debug.print("result: {}\n", .{current_ray});
    result = @as(u32, @intFromFloat(@abs(current_ray[0]))) + (@as(u32, @intFromFloat(@abs(current_ray[1]))) * 32 ) + (@as(u32, @intFromFloat(@abs(current_ray[2]))) * 32 * 32);
    //const end: zm.Vec = origin + look;
    //var inside_origin: zm.Vec = origin;
//    const ratio = zm.lengthSq3(look);
//    while (inside_origin[0] < chunk_pos[0] or inside_origin[0] > chunk_pos[0] + 32.0)
//    {
//        inside_origin[0] + ratio[0];
//    }

    //var empty = true;
    //while (empty)
    //{

    //    if (chunk_data[index] != 0)
    //    {
    //        empty = false;
    //    }
    //}

    return result;
}
