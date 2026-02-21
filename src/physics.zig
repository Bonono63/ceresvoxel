//!Physics simulation runtime and data structures
const std = @import("std");
const zm = @import("zmath");
const cm = @import("ceresmath.zig");
const chunk = @import("chunk.zig");
const main = @import("main.zig");

pub const GRAVITATIONAL_CONSTANT: f128 = 6.67428e-11;
pub const AU: f128 = 149.6e9;
pub const SCALE: f32 = 50.0;

const MAX_CONTACT_LIFETIME: u32 = 4;

pub const Contact = struct {
    best_index: u8,
    lifetime: u8,
    penetration: f32,
    restitution: f32, // how close to ellastic vs inellastic
    friction: f32,
    position: zm.Vec,
    normal: zm.Vec,
    a: *main.Object,
    b: *main.Object,
};

/// Integrates all linear forces, torques, angular velocities, linear velocities, positions,
/// and orientations for the physics objects in the simulation
///
/// delta_time: the time in milliseconds since the last physics_tick call
///
/// sim_start_time: the first time the simulation was started
/// (Created on world start) (UNIX time stamp)
///
/// sun_index: the index of the sun in @bodies
///
/// bodies: the bodies to be simulated over
pub fn physics_tick(
    delta_time: f64,
    sim_start_time: i64,
    bodies: []main.Object,
    contacts: *std.ArrayList(Contact),
) !void {
    // Planetary Motion
    for (0..bodies.len) |index| {
        if (bodies[index].planet) {
            // TODO make the orbit have an offset according to the barocenter
            // TODO Use eccentricity to skew one axis (x or z), the barocenter will have to be adjusted for more accurate
            // deterministic motion
            const time = @as(f64, @floatFromInt(std.time.milliTimestamp() - sim_start_time)) / @as(f32, @floatCast(bodies[index].orbit_radius));
            const x: f128 = bodies[index].orbit_radius * @cos(time / 8.0) + bodies[index].barycenter[0];
            const z: f128 = bodies[index].orbit_radius * @sin(time / 8.0) + bodies[index].barycenter[1];
            const y: f128 = bodies[index].eccliptic_offset[0] * x + bodies[index].eccliptic_offset[1] * z;

            bodies[index].position = .{ x, y, z };
            bodies[index].velocity = zm.normalize3(.{ -@as(f32, @floatCast(z)), @as(f32, @floatCast(y)), @as(f32, @floatCast(x)), 0.0 });
        }
    }

    integration(bodies, delta_time);

    // Force Accumulation
    // Gravity
    // Bouyancy
    // Magnetism

    // Contact Generation

    for (0..bodies.len) |i| {
        bodies[i].colliding = main.CollisionType.NONE;
    }

    // TODO implement 3D sweep and prune
    //const start_time = std.time.milliTimestamp();
    for (0..bodies.len) |a| {
        for ((a + 1)..bodies.len) |b| {
            if (a != b) {
                // TODO make this distance check according to half size instead of arbitrary
                if (cm.distance_f128(bodies[a].position, bodies[b].position) < 300.0) {
                    try generate_contacts(&bodies[a], &bodies[b], contacts);
                }
            }
        }
    }

    // TODO use simultaneuos collision resolution eventually since it will be more
    // accurate. But also much harder to implement and require a re understanding
    // of how we apply forces. A decision should probably be made on whether that approach
    // is our ultimate solution or not before we implement too much physics breaking stuff
    for (contacts.items, 0..contacts.items.len) |contact, index| {
        _ = &contact;
        _ = &index;

        // Cull contacts
        // if (contact.lifetime > MAX_CONTACT_LIFETIME) {
        //     _ = contacts.;
        // } else {}

        // contacts.items[index].lifetime += 1;

        contacts.clearRetainingCapacity();

        // resolve collisions (apply torques)
        //generate_impulses();
    }
}

/// Classical Mechanics (Integrator)
pub fn integration(objects: []main.Object, delta_time: f64) void {
    for (0..objects.len) |index| {
        if (objects[index].inverse_mass > 0.0) {
            // linear acceleration integration
            const resulting_linear_acceleration = cm.scale_f32(
                objects[index].force_accumulation,
                objects[index].inverse_mass * @as(f32, @floatCast(delta_time)),
            );

            objects[index].velocity += .{
                resulting_linear_acceleration[0],
                resulting_linear_acceleration[1],
                resulting_linear_acceleration[2],
                0.0,
            };

            const resulting_angular_acceleration: zm.Vec = zm.mul(
                objects[index].inverse_inertia_tensor,
                objects[index].torque_accumulation,
            );

            objects[index].angular_velocity += cm.scale_f32(
                resulting_angular_acceleration,
                @as(f32, @floatCast(delta_time)),
            );

            // linear damping
            objects[index].velocity = cm.scale_f32(
                objects[index].velocity,
                objects[index].linear_damping,
            );

            // angular damping
            objects[index].angular_velocity = cm.scale_f32(
                objects[index].angular_velocity,
                objects[index].angular_damping,
            );

            // velocity integration
            objects[index].position += .{
                objects[index].velocity[0] * delta_time,
                objects[index].velocity[1] * delta_time,
                objects[index].velocity[2] * delta_time,
            };

            // angular velocity integration
            cm.q_add_vector(
                &objects[index].orientation,
                .{
                    objects[index].angular_velocity[0] * @as(f32, @floatCast(delta_time)),
                    objects[index].angular_velocity[1] * @as(f32, @floatCast(delta_time)),
                    objects[index].angular_velocity[2] * @as(f32, @floatCast(delta_time)),
                    0,
                },
            );

            objects[index].orientation = cm.qnormalize(objects[index].orientation);

            // reset forces
            objects[index].force_accumulation = .{ 0.0, 0.0, 0.0, 0.0 };
            objects[index].torque_accumulation = .{ 0.0, 0.0, 0.0, 0.0 };
        }
    }
}

/// produces a set of contacts between 2 bodies (boxes)
fn generate_contacts(
    a: *main.Object,
    b: *main.Object,
    contacts: *std.ArrayList(Contact),
) !void {
    const ab_center_line_f128 = b.*.position - a.*.position;
    // The cast is fine as long as the calculation
    // is between 2 bodies that are close enough to each other
    const ab_center_line: zm.Vec = .{
        @as(f32, @floatCast(ab_center_line_f128[0])),
        @as(f32, @floatCast(ab_center_line_f128[1])),
        @as(f32, @floatCast(ab_center_line_f128[2])),
        0.0,
    };

    var best_index: u32 = 100;
    var best_overlap: f32 = 10000.0;

    var are_penetrating: bool = false;

    // Box A axis'
    are_penetrating = try_axis(
        0,
        a.getXAxis(),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        1,
        a.getYAxis(),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        2,
        a.getZAxis(),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );

    // Box B axis'
    are_penetrating = are_penetrating and try_axis(
        3,
        b.getXAxis(),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        4,
        b.getYAxis(),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        5,
        b.getZAxis(),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );

    // MISC axis'
    are_penetrating = are_penetrating and try_axis(
        6,
        zm.cross3(a.getXAxis(), b.getXAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        7,
        zm.cross3(a.getXAxis(), b.getYAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        8,
        zm.cross3(a.getXAxis(), b.getZAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        9,
        zm.cross3(a.getYAxis(), b.getXAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        10,
        zm.cross3(a.getYAxis(), b.getYAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        11,
        zm.cross3(a.getYAxis(), b.getZAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        12,
        zm.cross3(a.getZAxis(), b.getXAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        13,
        zm.cross3(a.getZAxis(), b.getYAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        14,
        zm.cross3(a.getZAxis(), b.getZAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );

    if (are_penetrating) {
        a.colliding = main.CollisionType.COLLISION;
        b.colliding = main.CollisionType.COLLISION;
    }

    if (are_penetrating) {
        if (best_index < 3) {
            try vertex_face_contact(
                contacts,
                a,
                b,
                ab_center_line,
                best_index,
                best_overlap,
            );
        } else if (best_index < 6) {
            try vertex_face_contact(
                contacts,
                a,
                b,
                cm.scale_f32(ab_center_line, -1.0),
                best_index - 3,
                best_overlap,
            );
        } else {
            // TODO complete edge edge contact generation
            edge_edge_contact(
                contacts,
                a,
                b,
                best_index - 6,
                best_overlap,
                ab_center_line,
            );
        }
    }
}

fn try_axis(
    index: u32,
    axis: zm.Vec,
    a: *main.Object,
    b: *main.Object,
    center_line: zm.Vec,
    best_overlap: *f32,
    best_index: *u32,
) bool {
    if (zm.lengthSq3(axis)[0] < 0.0001) {
        return true;
    }

    const axis_normalized = zm.normalize3(axis);

    const overlap: f32 = penetration_on_axis(
        a,
        b,
        axis_normalized,
        center_line,
    );

    if (overlap < 0) {
        return false;
    }

    if (overlap < best_overlap.*) {
        best_overlap.* = overlap;
        best_index.* = index;
    }

    return true;
}

// TODO decide whether we need this atm
//fn box_ray_intersection(
//    half_size: zm.Vec,
//    transform: zm.Mat,
//    origin_pos: zm.Vec,
//    direction: zm.Vec,
//) bool {
//    const MAX_STEPS: u32 = 30;
//    var step: u32 = 0;
//    var result = false;
//    const dir_norm = zm.normalize3(direction) * 0.1;
//    while (!result and step < MAX_STEPS) {
//        result = point_box_test(half_size, transform, origin_pos + dir_norm * step);
//        step += 1;
//    }
//    return result;
//}
//
//fn point_box_test(
//    half_size: zm.Vec,
//    box_transform: zm.Mat,
//    point: zm.Vec,
//) bool {
//    var result = false;
//    const inverse_box_transform = zm.inverse(box_transform);
//    const relative_point = zm.mul(point, inverse_box_transform);
//
//    // TODO test other axis
//    if (relative_point[0] < half_size[0] and relative_point[0] > -half_size[0]) {
//        result = true;
//    }
//
//    return result;
//}

///
pub fn vertex_face_contact(
    list: *std.ArrayList(Contact),
    a: *main.Object,
    b: *main.Object,
    center_line: zm.Vec,
    best_index: u32,
    penetration: f32,
) !void {
    var normal: zm.Vec = a.getAxis(best_index);
    if (zm.dot3(a.getAxis(best_index), center_line)[0] > 0.0) {
        normal = cm.scale_f32(normal, -1.0);
    }

    var vertex: zm.Vec = b.half_size;
    // vertex of box 1 and face of box 2
    if (zm.dot3(b.getXAxis(), normal)[0] < 0.0) {
        vertex[0] = -vertex[0];
    }
    if (zm.dot3(b.getYAxis(), normal)[0] < 0.0) {
        vertex[1] = -vertex[1];
    }
    if (zm.dot3(b.getZAxis(), normal)[0] < 0.0) {
        vertex[2] = -vertex[2];
    }

    // TODO add materials for blocks and have the
    // friction and restitution derived from it
    const contact: Contact = .{
        .best_index = @intCast(best_index),
        .lifetime = 0,
        .normal = normal,
        .penetration = penetration,
        .position = zm.mul(b.transform(), vertex),
        .restitution = 1.0,
        .friction = 0.1,
        .a = a,
        .b = b,
    };

    list.appendAssumeCapacity(contact);
}

///
pub fn edge_edge_contact(
    list: *std.ArrayList(Contact),
    a: *main.Object,
    b: *main.Object,
    best_index: u32,
    penetration: f32,
    center_line: zm.Vec,
) void {
    // Edge-Edge contact between box 1 and box 2

    const a_axis_index: u32 = best_index / 3;
    const b_axis_index: u32 = best_index % 3;
    const a_axis = a.getAxis(a_axis_index);
    const b_axis = b.getAxis(b_axis_index);

    var axis = zm.normalize3(zm.cross3(a_axis, b_axis));

    if (zm.dot3(axis, center_line)[0] > 0.0) {
        axis = cm.scale_f32(axis, -1.0);
    }

    var point_on_edge_a: zm.Vec = a.half_size;
    var point_on_edge_b: zm.Vec = b.half_size;

    for (0..3) |i| {
        if (i == a_axis_index) {
            point_on_edge_a[i] = 0;
        } else if (zm.dot3(a.getAxis(@intCast(i)), axis)[0] > 0) {
            point_on_edge_a[i] = -point_on_edge_a[i];
        }

        if (i == b_axis_index) {
            point_on_edge_b[i] = 0;
        } else if (zm.dot3(b.getAxis(@intCast(i)), axis)[0] < 0) {
            point_on_edge_b[i] = -point_on_edge_b[i];
        }
    }

    point_on_edge_a = zm.mul(a.transform(), point_on_edge_a);
    point_on_edge_b = zm.mul(b.transform(), point_on_edge_b);

    // ref: contactPoint()
    var vertex: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 };

    const use_a_axis: bool = best_index > 2;

    const square_magnitude_a: f32 = zm.lengthSq3(a_axis)[0];
    const square_magnitude_b: f32 = zm.lengthSq3(b_axis)[0];
    const dot_product_ab: f32 = zm.dot3(a_axis, b_axis)[0];

    const to_St: zm.Vec = point_on_edge_a - point_on_edge_b;
    const dot_product_Sta_a: f32 = zm.dot3(a_axis, to_St)[0];
    const dot_product_Sta_b: f32 = zm.dot3(b_axis, to_St)[0];

    const denominator: f32 = square_magnitude_a * square_magnitude_b - dot_product_ab * dot_product_ab;

    if (@abs(denominator) < 0.0001) {
        if (use_a_axis) vertex = point_on_edge_a else vertex = point_on_edge_b;
    }

    const mua = (dot_product_ab * dot_product_Sta_b - square_magnitude_b * dot_product_Sta_a) / denominator;
    const mub = (square_magnitude_a * dot_product_Sta_b - dot_product_ab * dot_product_Sta_a) / denominator;

    if (mua > a.half_size[a_axis_index] or mua < -a.half_size[a_axis_index] or mub > b.half_size[b_axis_index] or mub < -b.half_size[b_axis_index]) {
        if (use_a_axis) vertex = point_on_edge_a else vertex = point_on_edge_b;
    } else {
        const contact_a = point_on_edge_a + cm.scale_f32(a_axis, mua);
        const contact_b = point_on_edge_b + cm.scale_f32(b_axis, mub);

        vertex = cm.scale_f32(contact_a, 0.5) + cm.scale_f32(contact_b, 0.5);
    }

    const contact: Contact = .{
        .best_index = @intCast(best_index),
        .lifetime = 0,
        .normal = axis,
        .penetration = penetration,
        .position = vertex,
        .restitution = 1.0,
        .friction = 0.1,
        .a = a,
        .b = b,
    };

    list.appendAssumeCapacity(contact);
}

/// Finds the penetrating depth of a Box A and a Box B on a given axis
/// (Seperating Axis Theorum)
///
/// box_a: transformations pertaining to box a
/// box_b: transformation pertaining to box b
/// axis: the axis box_a and box_b will be projected onto to test whether they overlap or not
/// ab_center_line: the vector from the center of box_a to box_b in world coordinates
fn penetration_on_axis(
    box_a: *main.Object,
    box_b: *main.Object,
    axis: zm.Vec,
    ab_center_line: zm.Vec,
) f32 {
    const a_projection: f32 =
        box_a.half_size[0] * @abs(zm.dot3(box_a.getXAxis(), axis)[0]) +
        box_a.half_size[1] * @abs(zm.dot3(box_a.getYAxis(), axis)[0]) +
        box_a.half_size[2] * @abs(zm.dot3(box_a.getZAxis(), axis)[0]);

    const b_projection: f32 =
        box_b.half_size[0] * @abs(zm.dot3(box_b.getXAxis(), axis)[0]) +
        box_b.half_size[1] * @abs(zm.dot3(box_b.getYAxis(), axis)[0]) +
        box_b.half_size[2] * @abs(zm.dot3(box_b.getZAxis(), axis)[0]);

    const distance: f32 = @abs(zm.dot3(axis, ab_center_line)[0]);

    return a_projection + b_projection - distance;
}

/// Produces a Orthonormal basis to the provided normal vector
/// This does not work well with friction though
fn orthonormal_basis(contact_vec: zm.Vec) zm.Mat {
    var result: zm.Mat = zm.identity();

    if (@abs(contact_vec[0]) > @abs(contact_vec[1])) {
        const scale_factor = 1.0 / @sqrt(contact_vec[0] * contact_vec[0] + contact_vec[2] * contact_vec[2]);
        const y_vec: zm.Vec = .{
            contact_vec[2] / scale_factor,
            0.0,
            contact_vec[0] / scale_factor,
            0.0,
        };

        const z_vec: zm.Vec = .{
            contact_vec[1] * y_vec[0],
            contact_vec[2] * y_vec[0] - contact_vec[0] * y_vec[2],
            -contact_vec[1] * y_vec[0],
            0.0,
        };
        result = .{
            contact_vec[0], y_vec[0], z_vec[0], 0.0,
            contact_vec[1], y_vec[1], z_vec[1], 0.0,
            contact_vec[2], y_vec[2], z_vec[2], 0.0,
            0.0,            0.0,      0.0,      0.0,
        };
    } else {
        const scale_factor = 1.0 / @sqrt(contact_vec[0] * contact_vec[0] + contact_vec[1] * contact_vec[1]);
        const y_vec: zm.Vec = .{
            contact_vec[2] / scale_factor,
            0.0,
            contact_vec[0] / scale_factor,
            0.0,
        };

        const z_vec: zm.Vec = .{
            contact_vec[1] * y_vec[0],
            contact_vec[2] * y_vec[0] - contact_vec[0] * y_vec[2],
            -contact_vec[1] * y_vec[0],
            0.0,
        };
        result = .{
            contact_vec[0], y_vec[0], z_vec[0], 0.0,
            contact_vec[1], y_vec[1], z_vec[1], 0.0,
            contact_vec[2], y_vec[2], z_vec[2], 0.0,
            0.0,            0.0,      0.0,      0.0,
        };
    }
    return result;
}

// TODO decide whether to switch to Jacobian based forces
//fn generate_impulses(contacts: std.ArrayListUnmanaged(Contact)) void {
//for (contacts) |contact| {
//if (@abs(contact.normal[0]) > @abs(contact.normal[1])) {
//const x: zm.Vec = contact.normal;
//const scale_factor: f32 = 1.0 / @sqrt(x[2] * x[2] + x[0] * x[0]);
//const z = .{ x[2] * scale_factor, 0.0, -x[0] * scale_factor, 0.0 };
//const y = .{ x[1] * z[0], z[0] * z[0] - x[0] * z[2], -x[1] * z[0], 0.0 };
//} else {
//const x: zm.Vec = contact.normal;
//const scale_factor: f32 = 1.0 / @sqrt(x[2] * x[2] + x[0] * x[0]);
//const z = .{ x[2] * scale_factor, 0.0, -x[0] * scale_factor, 0.0 };
//const y = .{ x[1] * z[0], z[0] * z[0] - x[0] * z[2], -x[1] * z[0], 0.0 };
//}
//}
//}
//
