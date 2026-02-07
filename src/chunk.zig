//!Voxel storage, manipulation, and generation. Still WIP
const std = @import("std");
const zm = @import("zmath");
const vulkan = @import("vulkan.zig");

/// Stores block and related metadata
pub const Chunk = struct {
    empty: bool = true,
    block_occupancy: [1024]u32,
    blocks: [32768]u8,
    vertex_buffer: vulkan.VertexBuffer = undefined,
    lod: u32 = 0,
};
//TODO add chunk saving and loading

///The fundamental structure of any array of voxels
//pub const VoxelSpace = struct {
//    size: @Vector(3, u32),
//};

/// Returns a chunk with of random noise for voxels
///
/// seed: the world specific RNG seed (unused)
/// planet_index: unused
/// chunk_pos: unused
///
/// return: a 32**3 slice of voxel values
pub fn get_chunk_data_random(seed: u64) ![32768]u8 {
    var result: [32768]u8 = undefined;

    var random = std.Random.Xoshiro256.init(seed); // + planet_index + chunk_pos[0] + chunk_pos[1] + chunk_pos[2]);
    for (0..result.len) |index| {
        result[index] = random.random().int(u2);
    }

    return result;
}

pub fn get_chunk_data_sun() ![32768]u8 {
    var result: [32768]u8 = undefined;
    @memset(@as([]u8, @ptrCast(result[0..32768])), 2);
    return result;
}

/// Returns a chunk with one voxel in its corner
///
/// seed: the world specific RNG seed (unused)
/// planet_index: unused
/// chunk_pos: unused
///
/// return: a 32**3 slice of voxel values
pub fn get_chunk_data(seed: u64, planet_index: u32, chunk_pos: @Vector(3, u32)) ![32768]u8 {
    var result: [32768]u8 = undefined;
    _ = &planet_index;
    _ = &chunk_pos;
    _ = &seed;

    for (0..result.len) |index| {
        result[index] = 0;
    }

    result[0] = 4;
    //result[1] = 4;
    //result[2] = 4;
    //result[33] = 4;
    //result[65] = 4;

    return result;
}
