const zm = @import("zmath");
const std = @import("std");

pub const Mat3 = @Vector(9, f32);

pub fn identity() Mat3 {
    return .{1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0};
}

pub fn mul(a: Mat3, b: @Vector(3, f32)) @Vector(3, f32) {
    return .{a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
            a[3] * b[0] + a[4] * b[1] + a[5] * b[2],
            a[6] * b[0] + a[7] * b[1] + a[8] * b[2]
    };
}

pub fn scale_f32(vec: zm.Vec, scale: f32) zm.Vec {
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale, vec[3]};
}

pub fn scale_f64(vec: @Vector(3, f64), scale: f64) @Vector(3, f64){
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale};
}

pub fn scale_f128(vec: @Vector(3, f128), scale: f128) @Vector(3, f128){
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale};
}

pub fn normalize_f128(a: @Vector(3, f128)) @Vector(3, f128) {
    const d = distance_f128(a, .{0.0,0.0,0.0});
    return .{a[0]/d, a[1]/d, a[2]/d};
}

pub fn distance_f128(a: @Vector(3, f128), b: @Vector(3, f128)) f128 {
    const x = a[0] - b[0];
    const y = a[1] - b[1];
    const z = a[2] - b[2];
    return std.math.sqrt(x * x) + std.math.sqrt(y * y) + std.math.sqrt(z * z);
}

pub fn qnormalize(a: zm.Quat) zm.Quat {
    const length = std.math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] + a[3]);
    return .{a[0] / length, a[1] / length, a[2] / length, a[3] / length};
}
