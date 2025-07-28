
pub fn scale3(vec: @Vector(4, f32), scale: f32) @Vector(4, f32) {
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale, vec[3]};
}

pub fn scale3_128(vec: @Vector(3, f128), scale: f32) @Vector(3, f32) {
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale, vec[3]};
}
