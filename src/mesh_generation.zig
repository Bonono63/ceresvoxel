//! Meshing algorithms
const std = @import("std");
const vulkan = @import("vulkan.zig");

pub fn basic_mesh(allocator : *const std.mem.Allocator, data : *[32768]u8) !std.ArrayList(vulkan.Vertex)
{
    _ = &data;
    var result : std.ArrayList(vulkan.Vertex) = std.ArrayList(vulkan.Vertex).init(allocator.*);

    const block_count = 2.0;

    for (data[0..32768], 0..32768) |val, index|
    {
        if (val != 0){
            const step: f32 = 1.0/block_count;
            const uv_index: f32 = step * @as(f32, @floatFromInt(val-1));
            const tl = .{0.0,uv_index,1.0};
            const bl = .{0.0,uv_index+step,1.0};
            const tr = .{1.0,uv_index,1.0};
            const br = .{1.0,uv_index+step,1.0};
            const i : u32 = @intCast(index);
            const x : f32 = @floatFromInt(i % 32);
            const y : f32 = @floatFromInt(i / 32 % 32);
            const z : f32 = @floatFromInt(i / 32 / 32 % 32);
            
            //Front
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = br });
            try result.append(.{.pos = .{ x, y + 1.0, z }, .color = bl });
            try result.append(.{.pos = .{ x, y, z }, .color = tl });
            
            try result.append(.{.pos = .{ x, y, z }, .color = tl });
            try result.append(.{.pos = .{ x + 1.0, y, z }, .color = tr });
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = br });

            //Right
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = bl });
            try result.append(.{.pos = .{ x + 1.0, y, z }, .color = tl });
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = br });
            
            try result.append(.{.pos = .{ x + 1.0, y, z }, .color = tl });
            try result.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = tr });
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = br });

            //Back
            try result.append(.{.pos = .{ x, y, z + 1.0 }, .color = tr });
            try result.append(.{.pos = .{ x, y + 1.0, z + 1.0 }, .color = br });
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = bl });
            
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = bl });
            try result.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = tl });
            try result.append(.{.pos = .{ x, y, z + 1.0 }, .color = tr });
            
            //Left
            try result.append(.{.pos = .{ x, y, z + 1.0}, .color = tl });
            try result.append(.{.pos = .{ x, y, z }, .color = tr });
            try result.append(.{.pos = .{ x, y + 1.0, z }, .color = br });
            
            try result.append(.{.pos = .{ x, y, z + 1.0}, .color = tl });
            try result.append(.{.pos = .{ x, y + 1.0, z }, .color = br });
            try result.append(.{.pos = .{ x, y + 1.0, z + 1.0 }, .color = bl });
            
            //Bottom
            try result.append(.{.pos = .{ x, y + 1.0, z }, .color = tl });
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z}, .color = tr });
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = br });
            
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = br });
            try result.append(.{.pos = .{ x, y + 1.0, z + 1.0}, .color = bl });
            try result.append(.{.pos = .{ x, y + 1.0, z }, .color = tl });
            
            //Top
            try result.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = tr });
            try result.append(.{.pos = .{ x + 1.0, y, z}, .color = br });
            try result.append(.{.pos = .{ x, y, z }, .color = bl });
            
            try result.append(.{.pos = .{ x, y, z }, .color = bl });
            try result.append(.{.pos = .{ x, y, z + 1.0}, .color = tl });
            try result.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = tr });
        }
    }
    
    std.debug.print("vertex len: {}\n", .{result.items.len});

    return result;
}

fn pos_to_index(x: u32, y: u32, z: u32) u32
{
    return x + y*32 + z*32*32;
}

