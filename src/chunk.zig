const std = @import("std");
const zm = @import("zmath");

pub const VoxelSpace = struct {
    size: @Vector(3, u32),
    //pos: @Vector(3, f64),
    //rot: zm.Quat = zm.qidentity(),
    render_index: u32 = undefined,
    physics_index: u32 = undefined,
};

/// Either read or generate data live based on whether the chunk has been modified or not etc.
pub fn get_chunk_data_random(seed: u64, planet_index: u32, chunk_pos: @Vector(3,u32)) ![32768]u8 {
    var result: [32768]u8 = undefined;
    _ = &planet_index;
    _ = &chunk_pos;

    var random = std.Random.Xoshiro256.init(seed);// + planet_index + chunk_pos[0] + chunk_pos[1] + chunk_pos[2]);
    for (0..result.len) |index| {
        result[index] = random.random().int(u2);
    }

    return result;
}

/// Either read or generate data live based on whether the chunk has been modified or not etc.
pub fn get_chunk_data(seed: u64, planet_index: u32, chunk_pos: @Vector(3,u32)) ![32768]u8 {
    var result: [32768]u8 = undefined;
    _ = &planet_index;
    _ = &chunk_pos;
    _ = &seed;

    for (0..result.len) |index| {
        result[index] = 0;
    }

    result[0] = 4;
    result[1] = 4;
    result[2] = 4;
    result[33] = 4;
    result[65] = 4;

    return result;
}
