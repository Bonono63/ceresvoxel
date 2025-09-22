//!Chunk meshing algorithms
const std = @import("std");
const vulkan = @import("vulkan.zig");

// TODO Cull faces in between chunks
// TODO add a greedy meshing algorithm
// TODO add a lattice algorithm
// TODO add a glass panes algorithm

pub const style = enum {
    basic,
    cull,
    greedy,
    greedyVertexPull,
    lattice,
    glassPane
};

// Number of blocks in blocks.png
const BLOCK_COUNT: f32 = 4.0;

/// An unoptimized simple voxel meshing algorithm.
/// This is meant to be used as a baseline, nearly any other algorithm will produce better results.
///
/// data: voxel values; 0 being air, anything larger corresponding to the texture of a different block
/// chunk_index: the index of the chunk's model matrix on the GPU
/// list: a list to append the generated vertices to, this is useful for producing larger meshes
/// containing more than one chunk (Should be deprecated)
///
/// return: number of new additions to the given array list
pub fn BasicMesh(
    data : *const [32768]u8,
    chunk_index: u32,
    allocator: *std.mem.Allocator,
    list: *std.ArrayList(vulkan.ChunkVertex)
    ) !u32 {
    var size: u32 = 0;

    for (data[0..32768], 0..32768) |val, index| {
        if (val != 0) {
            const step: f32 = 1.0/BLOCK_COUNT;
            const uv_index: f32 = step * @as(f32, @floatFromInt(val-1));
            const tl = .{0.0,uv_index};
            const bl = .{0.0,uv_index+step};
            const tr = .{1.0,uv_index};
            const br = .{1.0,uv_index+step};
            const i : u32 = @intCast(index);
            const x : f32 = @floatFromInt(i % 32);
            const y : f32 = @floatFromInt(i / 32 % 32);
            const z : f32 = @floatFromInt(i / 32 / 32 % 32);
            
            //Front
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y + 1.0, z }, .uv = tl, .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y + 1.0, z }, .uv = tr, .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y, z }, .uv = br , .index = chunk_index});
            
            try list.append(allocator.*, .{.pos = .{ x, y, z }, .uv = br , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y, z }, .uv = bl , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y + 1.0, z }, .uv = tl , .index = chunk_index});

            //Right
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y + 1.0, z }, .uv = tr , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y, z }, .uv = br , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tl , .index = chunk_index});
            
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y, z }, .uv = br , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y, z + 1.0 }, .uv = bl , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tl , .index = chunk_index});

            //Back
            try list.append(allocator.*, .{.pos = .{ x, y, z + 1.0 }, .uv = bl , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y + 1.0, z + 1.0 }, .uv = tl , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tr , .index = chunk_index});
            
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tr , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y, z + 1.0 }, .uv = br , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y, z + 1.0 }, .uv = bl , .index = chunk_index});
            
            //Left
            try list.append(allocator.*, .{.pos = .{ x, y, z + 1.0}, .uv = br , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y, z }, .uv = bl , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y + 1.0, z }, .uv = tl , .index = chunk_index});
            
            try list.append(allocator.*, .{.pos = .{ x, y, z + 1.0}, .uv = br , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y + 1.0, z }, .uv = tl , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y + 1.0, z + 1.0 }, .uv = tr , .index = chunk_index});
            
            //Bottom
            try list.append(allocator.*, .{.pos = .{ x, y + 1.0, z }, .uv = br , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y + 1.0, z}, .uv = bl , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tl , .index = chunk_index});
            
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tl , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y + 1.0, z + 1.0}, .uv = tr , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y + 1.0, z }, .uv = br , .index = chunk_index});
            
            //Top
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y, z + 1.0 }, .uv = bl , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y, z}, .uv = tl , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y, z }, .uv = tr , .index = chunk_index});
            
            try list.append(allocator.*, .{.pos = .{ x, y, z }, .uv = tr , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x, y, z + 1.0}, .uv = br , .index = chunk_index});
            try list.append(allocator.*, .{.pos = .{ x + 1.0, y, z + 1.0 }, .uv = bl , .index = chunk_index});
            size += 36;
        }
    }
    return size;
}

/// A simple voxel meshing algorithm.
/// This algorithm provides voxels without faces in between them.
/// This mildly improves graphics performance and upload times, but the algorithm itself
/// it still relatively slow asside from ensuring there is enough unused space and appending with 
/// assumed available capacity
///
/// data: voxel values; 0 being air, anything larger corresponding to the texture of a different block
/// chunk_index: the index of the chunk's model matrix on the GPU
/// list: a list to append the generated vertices to, this is useful for producing larger meshes
/// containing more than one chunk (Should be deprecated)
///
/// return: number of new additions to the given array list
pub fn CullMesh(data : *const [32768]u8, chunk_index: u32, allocator: *std.mem.Allocator, list: *std.ArrayList(vulkan.ChunkVertex)) !u32
{
    _ = &chunk_index;
    var size: u32 = 0;

    for (data[0..32768], 0..32768) |val, index| {
        try list.ensureUnusedCapacity(allocator.*, 2048);
        if (val != 0) {
            const step: f32 = 1.0/BLOCK_COUNT;
            const uv_index: f32 = step * @as(f32, @floatFromInt(val-1));
            const tl = .{0.0,uv_index};
            const bl = .{0.0,uv_index+step};
            const tr = .{1.0,uv_index};
            const br = .{1.0,uv_index+step};
            
            const i : u32 = @intCast(index);
            const x : f32 = @floatFromInt(i % 32);
            const y : f32 = @floatFromInt(i / 32 % 32);
            const z : f32 = @floatFromInt(i / 32 / 32 % 32);

            if (index % 32 < 31) {
                const xp = data[index+1];
                if (xp == 0) {
                    //Right
                    list.appendAssumeCapacity(.{
                        .pos = .{ x + 1.0, y + 1.0, z },
                        .uv = tr,
                        .index = chunk_index 
                    });
                    list.appendAssumeCapacity(.{
                        .pos = .{ x + 1.0, y, z },
                        .uv = br,
                        .index = chunk_index
                    });
                    list.appendAssumeCapacity(.{
                        .pos = .{ x + 1.0, y + 1.0, z + 1.0 },
                        .uv = tl,
                        .index = chunk_index
                    });
                    
                    list.appendAssumeCapacity(.{
                        .pos = .{ x + 1.0, y, z },
                        .uv = br,
                        .index = chunk_index
                    });
                    list.appendAssumeCapacity(.{
                        .pos = .{ x + 1.0, y, z + 1.0 },
                        .uv = bl,
                        .index = chunk_index
                    });
                    list.appendAssumeCapacity(.{
                        .pos = .{ x + 1.0, y + 1.0, z + 1.0 },
                        .uv = tl,
                        .index = chunk_index
                    });
                }
            } else {
                //Right
                list.appendAssumeCapacity(.{
                    .pos = .{ x + 1.0, y + 1.0, z },
                    .uv = tr,
                    .index = chunk_index
                });
                list.appendAssumeCapacity(.{
                    .pos = .{ x + 1.0, y, z },
                    .uv = br,
                    .index = chunk_index
                });
                list.appendAssumeCapacity(.{
                    .pos = .{ x + 1.0, y + 1.0, z + 1.0 },
                    .uv = tl,
                    .index = chunk_index
                });
                
                list.appendAssumeCapacity(.{
                    .pos = .{ x + 1.0, y, z },
                    .uv = br,
                    .index = chunk_index
                });
                list.appendAssumeCapacity(.{
                    .pos = .{ x + 1.0, y, z + 1.0 },
                    .uv = bl,
                    .index = chunk_index
                });
                list.appendAssumeCapacity(.{
                    .pos = .{ x + 1.0, y + 1.0, z + 1.0 },
                    .uv = tl,
                    .index = chunk_index
                });
            }

            if (index % 32 > 0) {
                const xn = data[index-1];
                if (xn == 0) {
                    //Left
                    list.appendAssumeCapacity(.{
                        .pos = .{ x, y, z + 1.0},
                        .uv = br,
                        .index = chunk_index });
                    list.appendAssumeCapacity(.{
                        .pos = .{ x, y, z },
                        .uv = bl,
                        .index = chunk_index
                    });
                    list.appendAssumeCapacity(.{
                        .pos = .{ x, y + 1.0, z },
                        .uv = tl,
                        .index = chunk_index
                    });
                    
                    list.appendAssumeCapacity(.{
                        .pos = .{ x, y, z + 1.0},
                        .uv = br,
                        .index = chunk_index
                    });
                    list.appendAssumeCapacity(.{
                        .pos = .{ x, y + 1.0, z },
                        .uv = tl,
                        .index = chunk_index
                    });
                    list.appendAssumeCapacity(.{
                        .pos = .{ x, y + 1.0, z + 1.0 },
                        .uv = tr,
                        .index = chunk_index
                    });
                }
            } else {
                //Left
                list.appendAssumeCapacity(.{
                    .pos = .{ x, y, z + 1.0},
                    .uv = br,
                    .index = chunk_index
                });
                list.appendAssumeCapacity(.{
                    .pos = .{ x, y, z },
                    .uv = bl,
                    .index = chunk_index
                });
                list.appendAssumeCapacity(.{
                    .pos = .{ x, y + 1.0, z },
                    .uv = tl,
                    .index = chunk_index
                });
                
                list.appendAssumeCapacity(.{
                    .pos = .{ x, y, z + 1.0},
                    .uv = br,
                    .index = chunk_index
                });
                list.appendAssumeCapacity(.{
                    .pos = .{ x, y + 1.0, z },
                    .uv = tl,
                    .index = chunk_index
                });
                list.appendAssumeCapacity(.{
                    .pos = .{ x, y + 1.0, z + 1.0 },
                    .uv = tr,
                    .index = chunk_index
                });
            }

            if (index / 32 / 32 % 32 < 31) {
                const zp = data[index + 32*32];
                if (zp == 0) {
                    //Back
                    list.appendAssumeCapacity(.{.pos = .{ x, y, z + 1.0 }, .uv = bl, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x, y + 1.0, z + 1.0 }, .uv = tl, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tr, .index = chunk_index });
                    
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tr, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y, z + 1.0 }, .uv = br, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x, y, z + 1.0 }, .uv = bl, .index = chunk_index });
                }

            } else {
                //Back
                list.appendAssumeCapacity(.{.pos = .{ x, y, z + 1.0 }, .uv = bl, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x, y + 1.0, z + 1.0 }, .uv = tl, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tr, .index = chunk_index });
                
                list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tr, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y, z + 1.0 }, .uv = br, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x, y, z + 1.0 }, .uv = bl, .index = chunk_index });
            }
            
            if (index / 32 / 32 % 32 > 0) {
                const zn = data[index - 32*32];
                if (zn == 0) {
                    //Front
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z }, .uv = tl, .index = chunk_index});
                    list.appendAssumeCapacity(.{.pos = .{ x, y + 1.0, z }, .uv = tr, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x, y, z }, .uv = br, .index = chunk_index });
                    
                    list.appendAssumeCapacity(.{.pos = .{ x, y, z }, .uv = br, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y, z }, .uv = bl, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z }, .uv = tl, .index = chunk_index });

                    size += 6;
                }
            } else {
                //Front
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z }, .uv = tl, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x, y + 1.0, z }, .uv = tr, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x, y, z }, .uv = br, .index = chunk_index });
                    
                    list.appendAssumeCapacity(.{.pos = .{ x, y, z }, .uv = br, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y, z }, .uv = bl, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z }, .uv = tl, .index = chunk_index });

                size += 6;
            }

            if (index / 32 % 32 < 31) {
                const yp = data[index + 32];
                if (yp == 0) {
                    //Bottom
                    list.appendAssumeCapacity(.{.pos = .{ x, y + 1.0, z }, .uv = br, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z}, .uv = bl, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tl, .index = chunk_index });
                    
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tl, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x, y + 1.0, z + 1.0}, .uv = tr, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x, y + 1.0, z }, .uv = br, .index = chunk_index });
                }
            } else {
                //Bottom
                list.appendAssumeCapacity(.{.pos = .{ x, y + 1.0, z }, .uv = br, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z}, .uv = bl, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tl, .index = chunk_index });
                
                list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y + 1.0, z + 1.0 }, .uv = tl, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x, y + 1.0, z + 1.0}, .uv = tr, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x, y + 1.0, z }, .uv = br, .index = chunk_index });
            }

            if (index / 32 % 32 > 0) {
                const yn  = data[index - 32];
                if (yn == 0) {
                    //Top
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y, z + 1.0 }, .uv = bl, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y, z}, .uv = tl, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x, y, z }, .uv = tr, .index = chunk_index });
                    
                    list.appendAssumeCapacity(.{.pos = .{ x, y, z }, .uv = tr, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x, y, z + 1.0}, .uv = br, .index = chunk_index });
                    list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y, z + 1.0 }, .uv = bl, .index = chunk_index });
                }
            } else {
                //Top
                list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y, z + 1.0 }, .uv = bl, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y, z}, .uv = tl, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x, y, z }, .uv = tr, .index = chunk_index });
                
                list.appendAssumeCapacity(.{.pos = .{ x, y, z }, .uv = tr, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x, y, z + 1.0}, .uv = br, .index = chunk_index });
                list.appendAssumeCapacity(.{.pos = .{ x + 1.0, y, z + 1.0 }, .uv = bl, .index = chunk_index });
            }
        }
    }
    return size;
}

//pub fn lattice_chunk () []vulkan.Vertex
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
