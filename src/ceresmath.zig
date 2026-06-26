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

pub fn matFromQuat(q: zm.Quat) zm.Mat {
    return .{
        .{
            2 * (q[0] * q[0] + q[1] * q[1]) - 1,
            2 * (q[1] * q[2] - q[0] * q[3]),
            2 * (q[1] * q[3] + q[0] * q[2]),
            0.0,
        },
        .{
            2 * (q[1] * q[2] + q[0] * q[3]),
            2 * (q[0] * q[0] + q[2] * q[2]) - 1,
            2 * (q[2] * q[3] - q[0] * q[1]),
            0.0,
        },
        .{
            2 * (q[1] * q[3] - q[0] * q[2]),
            2 * (q[2] * q[3] + q[0] * q[1]),
            2 * (q[0] * q[0] + q[3] * q[3]) - 1,
            0.0,
        },
        .{
            0.0,
            0.0,
            0.0,
            1.0,
        },
    };
}

/// Technically inverting a cuboid tensor does not change anything so we don't
/// need to do any additional work than calculating the cuboid tensor
pub fn calculate_cuboid_inertia_tensor(
    mass: f32,
    half_size: @Vector(3, f32),
) [16]f32 {
    const x = half_size[0] * 2;
    const y = half_size[1] * 2;
    const z = half_size[2] * 2;
    const scale_factor: f32 = 1.0 / 12.0;

    return .{
        scale_factor * mass * (y * y + z * z), 0.0,                                   0.0,                                   0.0,
        0.0,                                   scale_factor * mass * (x * x + z * z), 0.0,                                   0.0,
        0.0,                                   0.0,                                   scale_factor * mass * (x * x + y * y), 0.0,
        0.0,                                   0.0,                                   0.0,                                   0.0,
    };
}

pub fn vector_product(a: zm.Vec, b: zm.Vec) zm.Vec {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
        0.0,
    };
}

pub fn scalar_product(a: zm.Vec, b: zm.Vec) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

pub fn matrix_component(x: zm.Vec, y: zm.Vec, z: zm.Vec) zm.Mat {
    return zm.matFromArr(.{
        x[0], y[0], z[0], 0.0,
        x[1], y[1], z[1], 0.0,
        x[2], y[2], z[2], 0.0,
        0.0,  0.0,  0.0,  0.0,
    });
}

/// casts from f128 vector to f32 vector **UNSAFE**
pub fn cast_position(pos: @Vector(3, f128)) zm.Vec {
    // TODO this function shouldn't have to exist, but we'll see how this turns out
    return .{
        @as(f32, @floatCast(pos[0])),
        @as(f32, @floatCast(pos[1])),
        @as(f32, @floatCast(pos[2])),
        0.0,
    };
}

pub fn scale_matrix(half_size: zm.Vec) zm.Mat {
    return .{
        .{ half_size[0], 0.0, 0.0, 0.0 },
        .{ 0.0, half_size[1], 0.0, 0.0 },
        .{ 0.0, 0.0, half_size[2], 0.0 },
        .{ 0.0, 0.0, 0.0, 0.5 },
    };
}

pub fn is_zero(f: f32) bool {
    return @abs(f) < 0.0001;
}

pub fn non_zero_vec(v: zm.Vec) bool {
    return @abs(v[0]) < 0.0001 and @abs(v[1]) < 0.0001 and @abs(v[2]) < 0.0001;
}

/// top answer: https://math.stackexchange.com/questions/40164/how-do-you-rotate-a-vector-by-a-unit-quaternion
/// Multiple a Vector by a Quaternion
pub fn mul_v_q(v: [4]f32, q: [4]f32) [4]f32 {
    const q_prime: [4]f32 = .{ q[0], -q[1], -q[2], -q[3] };
    var result = hamilton_product(q, v);
    result = hamilton_product(result, q_prime);

    return result;
}

/// https://en.wikipedia.org/wiki/Quaternion#Hamilton_product
fn hamilton_product(A: [4]f32, B: [4]f32) zm.Vec {
    return .{
        A[0] * B[0] - A[1] * B[1] - A[2] * B[2] - A[3] * B[3],
        A[0] * B[1] + A[1] * B[0] + A[2] * B[3] - A[3] * B[2],
        A[0] * B[2] - A[1] * B[3] + A[2] * B[0] + A[3] * B[1],
        A[0] * B[3] + A[1] * B[2] - A[2] * B[1] + A[3] * B[0],
    };
}

pub fn vToF3(v: zm.Vec) [3]f32 {
    return .{ v[0], v[1], v[2] };
}
