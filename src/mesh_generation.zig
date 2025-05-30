//! Meshing algorithms
const std = @import("std");
const vulkan = @import("vulkan.zig");

// TODO Cull faces in between chunks
// TODO add a greedy meshing algorithm
// TODO add a lattice algorithm
// TODO add a glass panes algorithm

pub fn basic_mesh(data : *[32768]u8, chunk_pos: @Vector(3, u8), list: *std.ArrayList(vulkan.Vertex)) !u32
{
    var size: u32 = 0;
    const block_count = 2.0;

    for (data[0..32768], 0..32768) |val, index| {
        if (val != 0) {
            const step: f32 = 1.0/block_count;
            const uv_index: f32 = step * @as(f32, @floatFromInt(val-1));
            const tl = .{0.0,uv_index,1.0};
            const bl = .{0.0,uv_index+step,1.0};
            const tr = .{1.0,uv_index,1.0};
            const br = .{1.0,uv_index+step,1.0};
            const i : u32 = @intCast(index);
            const x : f32 = @floatFromInt(i % 32 + chunk_pos[0] * 32);
            const y : f32 = @floatFromInt(i / 32 % 32 + chunk_pos[1] * 32);
            const z : f32 = @floatFromInt(i / 32 / 32 % 32 + chunk_pos[2] * 32);
            
            //Front
            try list.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = tl });
            try list.append(.{.pos = .{ x, y + 1.0, z }, .color = tr });
            try list.append(.{.pos = .{ x, y, z }, .color = br });
            
            try list.append(.{.pos = .{ x, y, z }, .color = br });
            try list.append(.{.pos = .{ x + 1.0, y, z }, .color = bl });
            try list.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = tl });

            //Right
            try list.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = tr });
            try list.append(.{.pos = .{ x + 1.0, y, z }, .color = br });
            try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });
            
            try list.append(.{.pos = .{ x + 1.0, y, z }, .color = br });
            try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = bl });
            try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });

            //Back
            try list.append(.{.pos = .{ x, y, z + 1.0 }, .color = bl });
            try list.append(.{.pos = .{ x, y + 1.0, z + 1.0 }, .color = tl });
            try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tr });
            
            try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tr });
            try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = br });
            try list.append(.{.pos = .{ x, y, z + 1.0 }, .color = bl });
            
            //Left
            try list.append(.{.pos = .{ x, y, z + 1.0}, .color = br });
            try list.append(.{.pos = .{ x, y, z }, .color = bl });
            try list.append(.{.pos = .{ x, y + 1.0, z }, .color = tl });
            
            try list.append(.{.pos = .{ x, y, z + 1.0}, .color = br });
            try list.append(.{.pos = .{ x, y + 1.0, z }, .color = tl });
            try list.append(.{.pos = .{ x, y + 1.0, z + 1.0 }, .color = tr });
            
            //Bottom
            try list.append(.{.pos = .{ x, y + 1.0, z }, .color = br });
            try list.append(.{.pos = .{ x + 1.0, y + 1.0, z}, .color = bl });
            try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });
            
            try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });
            try list.append(.{.pos = .{ x, y + 1.0, z + 1.0}, .color = tr });
            try list.append(.{.pos = .{ x, y + 1.0, z }, .color = br });
            
            //Top
            try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = bl });
            try list.append(.{.pos = .{ x + 1.0, y, z}, .color = tl });
            try list.append(.{.pos = .{ x, y, z }, .color = tr });
            
            try list.append(.{.pos = .{ x, y, z }, .color = tr });
            try list.append(.{.pos = .{ x, y, z + 1.0}, .color = br });
            try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = bl });
            size += 36;
        }
    }
    return size;
}

pub fn cull_mesh(data : *[32768]u8, chunk_pos: @Vector(3, u8), list: *std.ArrayList(vulkan.Vertex)) !u32
{
    var size: u32 = 0;
    const block_count = 2.0;

    for (data[0..32768], 0..32768) |val, index| {
        if (val != 0) {
            const step: f32 = 1.0/block_count;
            const uv_index: f32 = step * @as(f32, @floatFromInt(val-1));
            const tl = .{0.0,uv_index,1.0};
            const bl = .{0.0,uv_index+step,1.0};
            const tr = .{1.0,uv_index,1.0};
            const br = .{1.0,uv_index+step,1.0};
            const i : u32 = @intCast(index);
            const x : f32 = @floatFromInt(i % 32 + @as(u32, @intCast(chunk_pos[0])) * 32);
            const y : f32 = @floatFromInt(i / 32 % 32 + @as(u32, @intCast(chunk_pos[1])) * 32);
            const z : f32 = @floatFromInt(i / 32 / 32 % 32 + @as(u32, @intCast( chunk_pos[2])) * 32);

            if (index % 32 < 31) {
                const xp = data[index+1];
                if (xp == 0) {
                    //Right
                    try list.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = tr });
                    try list.append(.{.pos = .{ x + 1.0, y, z }, .color = br });
                    try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });
                    
                    try list.append(.{.pos = .{ x + 1.0, y, z }, .color = br });
                    try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = bl });
                    try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });
                }
            } else {
                //Right
                try list.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = tr });
                try list.append(.{.pos = .{ x + 1.0, y, z }, .color = br });
                try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });
                
                try list.append(.{.pos = .{ x + 1.0, y, z }, .color = br });
                try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = bl });
                try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });
            }

            if (index % 32 > 0) {
                const xn = data[index-1];
                if (xn == 0) {
                    //Left
                    try list.append(.{.pos = .{ x, y, z + 1.0}, .color = br });
                    try list.append(.{.pos = .{ x, y, z }, .color = bl });
                    try list.append(.{.pos = .{ x, y + 1.0, z }, .color = tl });
                    
                    try list.append(.{.pos = .{ x, y, z + 1.0}, .color = br });
                    try list.append(.{.pos = .{ x, y + 1.0, z }, .color = tl });
                    try list.append(.{.pos = .{ x, y + 1.0, z + 1.0 }, .color = tr });
                }
            } else {
                //Left
                try list.append(.{.pos = .{ x, y, z + 1.0}, .color = br });
                try list.append(.{.pos = .{ x, y, z }, .color = bl });
                try list.append(.{.pos = .{ x, y + 1.0, z }, .color = tl });
                
                try list.append(.{.pos = .{ x, y, z + 1.0}, .color = br });
                try list.append(.{.pos = .{ x, y + 1.0, z }, .color = tl });
                try list.append(.{.pos = .{ x, y + 1.0, z + 1.0 }, .color = tr });
            }

            if (index / 32 / 32 % 32 < 31) {
                const zp = data[index + 32*32];
                if (zp == 0) {
                    //Back
                    try list.append(.{.pos = .{ x, y, z + 1.0 }, .color = bl });
                    try list.append(.{.pos = .{ x, y + 1.0, z + 1.0 }, .color = tl });
                    try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tr });
                    
                    try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tr });
                    try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = br });
                    try list.append(.{.pos = .{ x, y, z + 1.0 }, .color = bl });
                }

            } else {
                //Back
                try list.append(.{.pos = .{ x, y, z + 1.0 }, .color = bl });
                try list.append(.{.pos = .{ x, y + 1.0, z + 1.0 }, .color = tl });
                try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tr });
                
                try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tr });
                try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = br });
                try list.append(.{.pos = .{ x, y, z + 1.0 }, .color = bl });
            }
            
            if (index / 32 / 32 % 32 > 0) {
                const zn = data[index - 32*32];
                if (zn == 0) {
                    //Front
                    try list.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = tl });
                    try list.append(.{.pos = .{ x, y + 1.0, z }, .color = tr });
                    try list.append(.{.pos = .{ x, y, z }, .color = br });
                    
                    try list.append(.{.pos = .{ x, y, z }, .color = br });
                    try list.append(.{.pos = .{ x + 1.0, y, z }, .color = bl });
                    try list.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = tl });
                }
            } else {
                //Front
                try list.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = tl });
                try list.append(.{.pos = .{ x, y + 1.0, z }, .color = tr });
                try list.append(.{.pos = .{ x, y, z }, .color = br });
                
                try list.append(.{.pos = .{ x, y, z }, .color = br });
                try list.append(.{.pos = .{ x + 1.0, y, z }, .color = bl });
                try list.append(.{.pos = .{ x + 1.0, y + 1.0, z }, .color = tl });
            }

            if (index / 32 % 32 < 31) {
                const yp = data[index + 32];
                if (yp == 0) {
                    //Bottom
                    try list.append(.{.pos = .{ x, y + 1.0, z }, .color = br });
                    try list.append(.{.pos = .{ x + 1.0, y + 1.0, z}, .color = bl });
                    try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });
                    
                    try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });
                    try list.append(.{.pos = .{ x, y + 1.0, z + 1.0}, .color = tr });
                    try list.append(.{.pos = .{ x, y + 1.0, z }, .color = br });
                }
            } else {
                //Bottom
                try list.append(.{.pos = .{ x, y + 1.0, z }, .color = br });
                try list.append(.{.pos = .{ x + 1.0, y + 1.0, z}, .color = bl });
                try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });
                
                try list.append(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .color = tl });
                try list.append(.{.pos = .{ x, y + 1.0, z + 1.0}, .color = tr });
                try list.append(.{.pos = .{ x, y + 1.0, z }, .color = br });
            }

            if (index / 32 % 32 > 0) {
                const yn  = data[index - 32];
                if (yn == 0) {
                    //Top
                    try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = bl });
                    try list.append(.{.pos = .{ x + 1.0, y, z}, .color = tl });
                    try list.append(.{.pos = .{ x, y, z }, .color = tr });
                    
                    try list.append(.{.pos = .{ x, y, z }, .color = tr });
                    try list.append(.{.pos = .{ x, y, z + 1.0}, .color = br });
                    try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = bl });
                }
            } else {
                //Top
                try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = bl });
                try list.append(.{.pos = .{ x + 1.0, y, z}, .color = tl });
                try list.append(.{.pos = .{ x, y, z }, .color = tr });
                
                try list.append(.{.pos = .{ x, y, z }, .color = tr });
                try list.append(.{.pos = .{ x, y, z + 1.0}, .color = br });
                try list.append(.{.pos = .{ x + 1.0, y, z + 1.0 }, .color = bl });
            }
            size += 36;
        }
    }
    return size;
}

fn pos_to_index(x: u32, y: u32, z: u32) u32
{
    return x + y*32 + z*32*32;
}

