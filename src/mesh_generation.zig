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

//pub fn lattice_chunk
////number of floats per vertex
//        const int vertex_stride = 6;
//        //number of vertices per index / number of vertices required for a face
//        const int index_stride = 6;
//        
//        long long int vertex_offset = 0;
//
//        printf("size: %d\n",size);
//        // 6 floats per vertex, width*2 + height*2 + depth*2 = face count, face_count * 6 * 6 * sizeof(float) = byte count
//        size_t face_count = size*6;
//        // face count * 6 vertices * 6 floats per vertex (3 floats for position, 3 for UV) * sizeof float (should be 4 bytes/32bits)
//        size_t float_count = face_count * index_stride * vertex_stride;
//        size_t byte_count = float_count*sizeof(float);
//        printf("size of float: %zu\n",sizeof(float));
//        printf("lattice chunk face count: %zu\n", face_count);
//        printf("float count: %zu\n",float_count);
//        printf("number of bytes for the lattice mesh: %zu\n", float_count*sizeof(float));
//        
//        *out = (float *) calloc(1, byte_count);
//        *out_size = byte_count;
//
//        if (*out == NULL)
//        {
//                printf("Unable to create lattice data heap.\n");
//        }
//        
//        // Negative Z faces
//        for (int z = 0 ; z < size ; z++)
//        {
//                float layer = ((float)z)/(size-1);
//                if (z == size-1)
//                        layer-=0.000001;
//                // BOTTOM FACE
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = -z*voxel_scale;
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = layer;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = -z*voxel_scale;
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = layer;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = -z*voxel_scale;
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = layer;
//
//                vertex_offset+=vertex_stride;
//
//                // TOP FACE
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = -z*voxel_scale;
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = layer;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = -z*voxel_scale;
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = layer;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = -z*voxel_scale;
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = layer;
//
//                vertex_offset+=vertex_stride;
//        }
//
//        // POSITIVE Z FACES
//        for (int z = 0 ; z < size ; z++)
//        {
//                float layer = ((float)z)/(size-1);
//                if (z == size-1)
//                        layer-=0.000001;
//                // BOTTOM FACE
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = -z*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = layer;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = -z*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = layer;
//
//                vertex_offset+=vertex_stride;
//
//
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = -z*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = layer;
//
//                vertex_offset+=vertex_stride;
//
//                // TOP FACE
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = -z*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = layer;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = -z*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = layer;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = -z*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = layer;
//        
//                vertex_offset+=vertex_stride;
//        }
//
//        // NEGATIVE X FACES
//        for (int x = 0 ; x < size ; x++)
//        {
//                float layer = 1.0f-((float)x)/(size-1);
//                if (x == 0)
//                        layer -= 0.000001;
//                // BOTTOM FACE
//                *(*out+vertex_offset+0) = x*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = 0.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = x*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = 1.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = x*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = 1.0f;
//
//                vertex_offset+=vertex_stride;
//
//                // TOP FACE
//                *(*out+vertex_offset+0) = x*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = 1.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = x*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = 0.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = x*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = 0.0f;
//        
//                vertex_offset+=vertex_stride;
//        }
//
//        // POSITIVE X FACES
//        for (int x = 0 ; x < size ; x++)
//        {
//                float layer = 1.0f-((float)x)/(size-1);
//                if (x == 0)
//                        layer -= 0.000001;
//                // BOTTOM FACE
//                *(*out+vertex_offset+0) = x*voxel_scale;
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = 1.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = x*voxel_scale;
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = 1.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = x*voxel_scale;
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = 0.0f;
//
//                vertex_offset+=vertex_stride;
//
//                // TOP FACE
//                *(*out+vertex_offset+0) = x*voxel_scale;
//                *(*out+vertex_offset+1) = 0.0f;
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 0.0f;
//                *(*out+vertex_offset+5) = 0.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = x*voxel_scale;
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = 0.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = x*voxel_scale;
//                *(*out+vertex_offset+1) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = layer;
//                *(*out+vertex_offset+4) = 1.0f;
//                *(*out+vertex_offset+5) = 1.0f;
//        
//                vertex_offset+=vertex_stride;
//        }
//
//        // NEGATIVE Y FACES
//        for (int y = 0 ; y < size ; y++)
//        {
//                float layer = ((float)y)/(size-1);
//                if (y == size-1)
//                        layer-=0.000001;
//                // BOTTOM FACE
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = y*voxel_scale;
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 1.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = y*voxel_scale;
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 0.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = y*voxel_scale;
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 0.0f;
//
//                vertex_offset+=vertex_stride;
//
//                // TOP FACE
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = y*voxel_scale;
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 0.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = y*voxel_scale;
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 1.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = y*voxel_scale;
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 1.0f;
//                
//                vertex_offset+=vertex_stride;
//        }
//
//        // POSITIVE Y FACES
//        for (int y = 0 ; y < size ; y++)
//        {
//                float layer = ((float)y)/(size-1);
//                if (y == size-1)
//                        layer-=0.000001;
//                // BOTTOM FACE
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = y*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 0.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = y*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 0.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = y*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 1.0f;
//
//                vertex_offset+=vertex_stride;
//
//                // TOP FACE
//                *(*out+vertex_offset+0) = 1.0f*voxel_scale*size;
//                *(*out+vertex_offset+1) = y*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 0.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 1.0f;
//
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = y*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+2) = -1.0f*voxel_scale*size+(1.0f*voxel_scale);
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 1.0f;
//                
//                vertex_offset+=vertex_stride;
//
//                *(*out+vertex_offset+0) = 0.0f;
//                *(*out+vertex_offset+1) = y*voxel_scale+(1.0f*voxel_scale);
//                *(*out+vertex_offset+2) = 1.0f*voxel_scale;
//                *(*out+vertex_offset+3) = 1.0f;
//                *(*out+vertex_offset+4) = layer;
//                *(*out+vertex_offset+5) = 0.0f;
//                
//                vertex_offset+=vertex_stride;
//        }
//}
