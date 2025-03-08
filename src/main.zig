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

    // TODO add some error handling where possible, although for most of this initialization stuff chances are we won't
    // be able to load into any kind of application if this all doesn't work out...
    //try create_surface(&instance);

    //try pick_physical_device(&instance, &allocator);

    //try create_graphics_queue(&instance, &allocator);

    //try create_swapchain(&instance, &allocator);

    //try create_swapchain_image_views(&instance, &allocator);

    //try create_graphics_pipeline(&instance, &allocator);

    //try create_framebuffers(&instance, &allocator);

    //try create_command_pool(&instance);

    //try create_command_buffer(&instance);

    //try create_sync_objects(&instance);

    _ = c.glfwSetKeyCallback(instance.window, key_callback);

    while (c.glfwWindowShouldClose(instance.window) == 0) {
        c.glfwPollEvents();

        //try draw_frame(&instance);
    }

    instance.cleanup(&allocator);
    //instance_clean_up(&instance, &allocator);
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

fn create_command_pool(instance: *vulkan.Instance) vulkan.VkAbstractionError!void {
    const command_pool_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = instance.queue_family_index,
    };

    const command_pool_success = c.vkCreateCommandPool(instance.device, &command_pool_info, null, &instance.command_pool);
    if (command_pool_success != c.VK_SUCCESS) {
        return vulkan.VkAbstractionError.FailedCommandPoolCreation;
    }
}

fn create_command_buffer(instance: *vulkan.Instance) vulkan.VkAbstractionError!void {
    const allocation_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = instance.command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    if (c.vkAllocateCommandBuffers(instance.device, &allocation_info, &instance.command_buffer) != c.VK_SUCCESS) {
        return vulkan.VkAbstractionError.CommandBufferAllocationFailed;
    }
}

fn record_command_buffer(instance: *vulkan.Instance, command_buffer: c.VkCommandBuffer, image_index: u32) vulkan.VkAbstractionError!void {
    _ = &image_index;

    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = 0,
        //.pInheretenceInfo = null,
    };

    if (c.vkBeginCommandBuffer(command_buffer, &begin_info) != c.VK_SUCCESS) {
        return vulkan.VkAbstractionError.UnableToBeginRenderPass;
    }

    const clear_color: c.VkClearValue = undefined;
    //std.debug.print("clear color [0]: {}\n", .{clear_color});

    const render_pass_info = c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = instance.renderpass,
        .framebuffer = instance.frame_buffers[image_index],
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = instance.swapchain_extent,
        },
        .clearValueCount = 1,
        .pClearValues = &clear_color,
    };

    c.vkCmdBeginRenderPass(command_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);

    c.vkCmdBindPipeline(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, instance.graphics_pipeline);

    const viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(instance.swapchain_extent.width),
        .height = @floatFromInt(instance.swapchain_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    c.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

    const scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = instance.swapchain_extent,
    };

    c.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

    c.vkCmdDraw(command_buffer, 3, 1, 0, 0);

    c.vkCmdEndRenderPass(command_buffer);
}

fn create_sync_objects(instance: *vulkan.Instance) vulkan.VkAbstractionError!void {
    const image_available_semaphore_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    const image_completion_semaphore_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    const in_flight_fence_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    const success_a = c.vkCreateSemaphore(instance.device, &image_available_semaphore_info, null, &instance.image_available_semaphore);
    const success_b = c.vkCreateSemaphore(instance.device, &image_completion_semaphore_info, null, &instance.image_completion_semaphore);
    const success_c = c.vkCreateFence(instance.device, &in_flight_fence_info, null, &instance.in_flight_fence);

    if (success_a != c.VK_SUCCESS or success_b != c.VK_SUCCESS or success_c != c.VK_SUCCESS) {
        return vulkan.VkAbstractionError.UnableToCreateSyncObect;
    }
}

fn draw_frame(instance: *vulkan.Instance) vulkan.VkAbstractionError!void {
    const fence_wait = c.vkWaitForFences(instance.device, 1, &instance.in_flight_fence, c.VK_TRUE, std.math.maxInt(u64));

    if (fence_wait != c.VK_SUCCESS) {
        return vulkan.VkAbstractionError.OutOfMemory;
    }

    var image_index: u32 = 0;

    const acquire_next_image_success = c.vkAcquireNextImageKHR(instance.device, instance.swapchain, std.math.maxInt(u64), instance.image_available_semaphore, null, &image_index);

    if (acquire_next_image_success != c.VK_SUCCESS) {
        std.debug.print("[Error] Unable to acquire next swapchain image: {} \n", .{acquire_next_image_success});
        return vulkan.VkAbstractionError.UnableToAcquireNextSwapchainImage;
    }

    const reset_fence_success = c.vkResetFences(instance.device, 1, &instance.in_flight_fence);
    if (reset_fence_success != c.VK_SUCCESS) {
        return vulkan.VkAbstractionError.OutOfMemory;
    }

    if (c.vkResetCommandBuffer(instance.command_buffer, 0) != c.VK_SUCCESS) {
        return vulkan.VkAbstractionError.OutOfMemory;
    }

    try record_command_buffer(instance, instance.command_buffer, image_index);

    // TODO Not sure if it makes sense to place this here or in the record_command_buffer call
    const end_recording_success = c.vkEndCommandBuffer(instance.command_buffer);
    if (end_recording_success != c.VK_SUCCESS) {
        return vulkan.VkAbstractionError.EndRecordingFailure;
    }

    //const wait_semaphores = [_]c.VkSemaphore{
    //    instance.image_available_semaphore,
    //};

    const wait_stages = [_]c.VkPipelineStageFlags{
        c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    };

    //const signal_semaphores: []c.VkSemaphore = .{instance.image_completion_semaphore};

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1, //wait_semaphores.len,
        .pWaitSemaphores = &instance.image_available_semaphore, //wait_semaphores.ptr,
        .pWaitDstStageMask = &wait_stages,
        .signalSemaphoreCount = 1, //signal_semaphores.len,
        .pSignalSemaphores = &instance.image_completion_semaphore, //signal_semaphores.ptr,
        .commandBufferCount = 1,
        .pCommandBuffers = &instance.command_buffer,
    };

    const queue_submit_success = c.vkQueueSubmit(instance.present_queue, 1, &submit_info, instance.in_flight_fence);
    if (queue_submit_success != c.VK_SUCCESS) {
        return vulkan.VkAbstractionError.OutOfMemory;
    }

    //const swapchains = []c.VkSwapchainKHR{instance.swapchain};

    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &instance.image_completion_semaphore,
        .swapchainCount = 1,
        .pSwapchains = &instance.swapchain, //swapchains,
        .pImageIndices = &image_index,
    };

    const present_success = c.vkQueuePresentKHR(instance.present_queue, &present_info);
    if (present_success != c.VK_SUCCESS) {
        return vulkan.VkAbstractionError.PresentationFailure;
    }
}

// TODO make sure to free like 70% of the objects I haven't bothered to, likely memory leaks in the swapchain code
fn instance_clean_up(instance: *vulkan.Instance, allocator: *const std.mem.Allocator) void {
    //c.vkDestroySemaphore();
    //c.vkDestroyFence();
    c.vkDestroyCommandPool(instance.device, instance.command_pool, null);
    //for framebuffer destroy
    //c.vkDestroyPipeline();
    //c.vkDestroyPipelineLayout();
    //c.vkDestroyRenderPass();
    //c.vkDestroyPipelineLayout();
    _ = allocator;
    //allocator.*.free(instance.swapchain_image_views);
}
