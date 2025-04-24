//! Meshing algorithms
const std = @import("std");
const vulkan = @import("vulkan.zig");

pub fn basic_mesh(allocator : *const std.mem.Allocator, data : *[32768]u8) !std.ArrayList(vulkan.Vertex)
{
    _ = &data;
    var result : std.ArrayList(vulkan.Vertex) = std.ArrayList(vulkan.Vertex).init(allocator.*);

    try result.append(.{ .pos = .{ -0.5, -0.5, 0.0 }, .color = .{ 1.0, 1.0, 1.0 } });
    try result.append(.{ .pos = .{ 0.5, -0.5, 0.0 }, .color = .{ 0.0, 1.0, 0.0 } });
    try result.append(.{ .pos = .{ 0.5, 0.5, 0.0 }, .color = .{ 0.0, 0.0, 1.0 } });

    try result.append(.{ .pos = .{ 0.5, 0.5, 0.0 }, .color = .{ 0.0, 0.0, 1.0 } });
    try result.append(.{ .pos = .{ -0.5, 0.5, 0.0 }, .color = .{ 1.0, 0.0, 0.0 } });
    try result.append(.{ .pos = .{ -0.5, -0.5, 0.0 }, .color = .{ 1.0, 1.0, 1.0 } });
    
    for (data[0..64], 0..64) |val, index|
    {
        if (val != 0){
            const i : u32 = @intCast(index);
            const x : f32 = @floatFromInt(i % 32);
            const y : f32 = @floatFromInt(i / 32 % 32);
            const z : f32 = @floatFromInt(i / 32 / 32 % 32);
            //Front
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x, y + 1.0, z }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x, y, z }, .color = .{ 1.0, 1.0, 1.0 }});
            
            try result.append(.{.pos = .{ x, y, z }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x + 1.0, y, z }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = .{ 0.0, 1.0, 1.0 }});

            //Right
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x + 1.0, y, z }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = .{ 1.0, 1.0, 1.0 }});
            
            try result.append(.{.pos = .{ x + 1.0, y, z }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = .{ 0.0, 1.0, 1.0 }});

            //Back
            try result.append(.{.pos = .{ x, y, z + 1.0 }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x, y + 1.0, z + 1.0 }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = .{ 1.0, 1.0, 1.0 }});
            
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = .{ 0.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x, y, z + 1.0 }, .color = .{ 1.0, 1.0, 1.0 }});
            
            //Left
            try result.append(.{.pos = .{ x, y, z + 1.0}, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x, y, z }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x, y + 1.0, z }, .color = .{ 1.0, 1.0, 1.0 }});
            
            try result.append(.{.pos = .{ x, y, z + 1.0}, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x, y + 1.0, z }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x, y + 1.0, z + 1.0 }, .color = .{ 0.0, 1.0, 1.0 }});
            
            //Bottom
            try result.append(.{.pos = .{ x, y + 1.0, z }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z}, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = .{ 1.0, 1.0, 1.0 }});
            
            try result.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x, y + 1.0, z + 1.0}, .color = .{ 1.0, 1.0, 1.0 }});
            try result.append(.{.pos = .{ x, y + 1.0, z }, .color = .{ 0.0, 1.0, 1.0 }});
        }
    }
    
    std.debug.print("vertex len: {}\n", .{result.items.len});

    return result;
}
