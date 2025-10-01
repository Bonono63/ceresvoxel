//!Various mathematical functions to fill in the gaps that zmath doesn't provide
const zm = @import("zmath");
const std = @import("std");

pub const Mat3 = @Vector(9, f32);

pub fn identity() Mat3 {
    return .{ 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0 };
}

pub fn mul(a: Mat3, b: @Vector(3, f32)) @Vector(3, f32) {
    return .{ a[0] * b[0] + a[1] * b[1] + a[2] * b[2], a[3] * b[0] + a[4] * b[1] + a[5] * b[2], a[6] * b[0] + a[7] * b[1] + a[8] * b[2] };
}

pub fn scale_f32(vec: zm.Vec, scale: f32) zm.Vec {
    return .{ vec[0] * scale, vec[1] * scale, vec[2] * scale, vec[3] };
}

pub fn scale_f64(vec: @Vector(3, f64), scale: f64) @Vector(3, f64) {
    return .{ vec[0] * scale, vec[1] * scale, vec[2] * scale };
}

pub fn scale_f128(vec: @Vector(3, f128), scale: f128) @Vector(3, f128) {
    return .{ vec[0] * scale, vec[1] * scale, vec[2] * scale };
}

pub fn normalize_f128(a: @Vector(3, f128)) @Vector(3, f128) {
    const d = distance_f128(a, .{ 0.0, 0.0, 0.0 });
    return .{ a[0] / d, a[1] / d, a[2] / d };
}

pub fn distance_f128(a: @Vector(3, f128), b: @Vector(3, f128)) f128 {
    const x = a[0] - b[0];
    const y = a[1] - b[1];
    const z = a[2] - b[2];
    return std.math.sqrt(x * x) + std.math.sqrt(y * y) + std.math.sqrt(z * z);
}

pub fn qnormalize(a: zm.Quat) zm.Quat {
    const length = a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3];
    if (length == 0) {
        return zm.qidentity();
    } else {
        const d = 1.0 / std.math.sqrt(length);
        return .{ a[0] * d, a[1] * d, a[2] * d, a[3] * d };
    }
}

pub fn q_add_vector(q: *zm.Quat, vec: zm.Vec) void {
    const temp: zm.Quat = zm.qmul(q.*, .{ 0, vec[0], vec[1], vec[2] });
    q.* += .{ temp[0] * 0.5, temp[1] * 0.5, temp[2] * 0.5, temp[3] * 0.5 };
}

pub fn projectV(a: zm.Vec, b: zm.Vec) zm.Vec {
    // proj b a = (a dot b_unit) unit_b
    const unit_b = zm.normalize3(b);
    return scale_f32(unit_b, zm.dot3(a, unit_b)[0]);
}

///// Inverse for inertia tensors
//pub fn inverse_mat3(m: Mat3) Mat3 {
//}
