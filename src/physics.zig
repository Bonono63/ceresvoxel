//!Physics simulation runtime and data structures
const std = @import("std");
const zm = @import("zmath");
const cm = @import("ceresmath.zig");
const chunk = @import("chunk.zig");
const main = @import("main.zig");

pub const GRAVITATIONAL_CONSTANT: f128 = 6.67428e-11;
pub const AU: f128 = 149.6e9;
pub const SCALE: f32 = 50.0;

pub const Contact = struct {
    penetration: f32,
    restitution: f32, // how close to ellastic vs inellastic
    friction: f32,
    position: zm.Vec,
    normal: zm.Vec,
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

    // Gravity
    // Bouyancy
    // Magnetism

    // Contact Generation

    // TODO implement 3D sweep and prune
    //const start_time = std.time.milliTimestamp();
    for (0..bodies.len) |a| {
        for ((a + 1)..bodies.len) |b| {
            if (a != b) {
                if (cm.distance_f128(bodies[a].position, bodies[b].position) < 32.0) {
                    try generate_contacts(&bodies[a], &bodies[b], contacts);
                }
            }
        }
    }

    for (contacts.items) |contact| {
        _ = &contact;
        // resolve collisions (apply torques)
    }
    // clear contacts

    integration(bodies, delta_time);
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
    const ab_center_line_f128 = a.*.position - b.*.position;
    // The cast is fine as long as the calculation
    // is between 2 bodies that are close enough to each other
    const ab_center_line: zm.Vec = .{
        @as(f32, @floatCast(ab_center_line_f128[0])),
        @as(f32, @floatCast(ab_center_line_f128[1])),
        @as(f32, @floatCast(ab_center_line_f128[2])),
        0.0,
    };

    var best_index: u32 = 0;
    var best_overlap: f32 = 10000.0;
    var penetration: bool = false;
    for (0..14) |i| {
        var axis: zm.Vec = SAT_axis(@intCast(i), a, b);

        if (zm.lengthSq3(axis)[0] < 0.0001) {
            penetration = true;
        } else {
            axis = zm.normalize3(axis);

            const overlap: f32 = penetration_on_axis(
                a.*.half_size,
                a.*.transform(),
                b.*.half_size,
                b.*.transform(),
                axis,
                ab_center_line,
            );

            if (overlap < 0) {
                penetration = false;
            }
            if (overlap < best_overlap) {
                best_overlap = overlap;
                best_index = @intCast(i);
            }
            penetration = true;
        }
    }

    if (penetration) {
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
            edge_edge_contact(
                contacts,
                a,
                b,
                best_index,
                best_overlap,
                ab_center_line,
            );
        }
    }
}

/// Produces the various axis' used in the SAT test
fn SAT_axis(i: u32, a: *main.Object, b: *main.Object) zm.Vec {
    var axis: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 };
    switch (i) {
        0 => {
            axis = a.getXAxis();
        },
        1 => {
            axis = a.getYAxis();
        },
        2 => {
            axis = a.getZAxis();
        },
        3 => {
            axis = b.getXAxis();
        },
        4 => {
            axis = b.getYAxis();
        },
        5 => {
            axis = b.getZAxis();
        },
        6 => {
            axis = zm.cross3(a.getXAxis(), b.getXAxis());
        },
        7 => {
            axis = zm.cross3(a.getXAxis(), b.getYAxis());
        },
        8 => {
            axis = zm.cross3(a.getXAxis(), b.getZAxis());
        },
        9 => {
            axis = zm.cross3(a.getYAxis(), b.getXAxis());
        },
        10 => {
            axis = zm.cross3(a.getYAxis(), b.getYAxis());
        },
        11 => {
            axis = zm.cross3(a.getYAxis(), b.getZAxis());
        },
        12 => {
            axis = zm.cross3(a.getZAxis(), b.getXAxis());
        },
        13 => {
            axis = zm.cross3(a.getZAxis(), b.getYAxis());
        },
        14 => {
            axis = zm.cross3(a.getZAxis(), b.getZAxis());
        },
        else => {},
    }
    return axis;
}

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
        .normal = normal,
        .penetration = penetration,
        .position = zm.mul(b.transform(), vertex),
        .restitution = 1.0,
        .friction = 0.1,
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

    const a_axis = a.getAxis(best_index / 3);
    const b_axis = b.getAxis(best_index % 3);

    var axis = zm.normalize3(zm.cross3(a_axis, b_axis));

    if (zm.dot3(axis, center_line)[0] > 0.0) {
        axis = cm.scale_f32(axis, -1.0);
    }

    var point_on_edge_one: zm.Vec = a.half_size;
    var point_on_edge_two: zm.Vec = b.half_size;

    for (0..3) |i| {
        if (i == best_index / 3) {
            point_on_edge_one[i] = 0;
        } else if (zm.dot3(a.getAxis(@intCast(i)), axis)[0] > 0) {
            point_on_edge_one[i] = -point_on_edge_one[i];
        }

        if (i == best_index % 3) {
            point_on_edge_two[i] = 0;
        } else if (zm.dot3(b.getAxis(@intCast(i)), axis)[0] < 0) {
            point_on_edge_two[i] = -point_on_edge_two[i];
        }
    }

    point_on_edge_one = zm.mul(a.transform(), point_on_edge_one);
    point_on_edge_two = zm.mul(b.transform(), point_on_edge_two);

    const vertex: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 };

    const contact: Contact = .{
        .normal = axis,
        .penetration = penetration,
        .position = vertex,
        .restitution = 1.0,
        .friction = 0.1,
    };

    list.appendAssumeCapacity(contact);
}

/// Finds the penetrating depth of a Box A and a Box B on a given axis
/// (Seperating Axis Theorum)
///
/// box_a: the half size of box a
/// transform_a: the model matrix (all rotations and translations) of box_a
/// box_b: the half size of box b
/// transform_b: the model matrix (all rotations and translations) of box_b
/// axis: the axis box_a and box_b will be projected onto to test whether they overlap or not
/// ab_center_line: the vector from the center of box_a to box_b in world coordinates
fn penetration_on_axis(
    box_a: zm.Vec,
    transform_a: zm.Mat,
    box_b: zm.Vec,
    transform_b: zm.Mat,
    axis: zm.Vec,
    ab_center_line: zm.Vec,
) f32 {
    const a_axis = zm.mul(transform_a, box_a);
    const b_axis = zm.mul(transform_b, box_b);

    const a_projected = cm.projectV(a_axis, axis);
    const b_projected = cm.projectV(b_axis, axis);

    const a_projected_length: f32 = zm.length3(a_projected)[0];
    const b_projected_length: f32 = zm.length3(b_projected)[0];

    const distance: f32 = zm.length3(cm.projectV(axis, ab_center_line))[0];

    return a_projected_length + b_projected_length - distance;
}
