//! Physics simulation runtime and data structures
//! This physics code is derived from the Cyclone Engine by Ian Millington
//! As well as Allen Chou's unity-physics-constraints tutorials.
//! As such this file is permissable under the MIT license

//MIT License
//
//Copyright (c) 2021 Ming-Lun "Allen" Chou
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all
//copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//SOFTWARE.

//The MIT License
//
//Copyright (c) 2003-2009 Ian Millington
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in
//all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//THE SOFTWARE.

const std = @import("std");
const zm = @import("zmath");
const cm = @import("ceresmath.zig");
const chunk = @import("chunk.zig");
const main = @import("main.zig");

pub const GRAVITATIONAL_CONSTANT: f128 = 6.67428e-11;
pub const AU: f128 = 149.6e9;
pub const SCALE: f32 = 50.0;

const MAX_CONTACT_LIFETIME: u32 = 4;
const MAX_VELOCITY_PER_FRAME: f32 = 0.25;

// TODO add friction
pub const Contact = struct {
    A: *main.Object,
    B: *main.Object,
    pA: zm.Vec,
    pB: zm.Vec,
    penetration: f32,
    normal: zm.Vec,
    rA: zm.Vec, // center of a to contact position
    rB: zm.Vec, // center of b to contact position

    jN: Jacobian, // Normal used for separation
    jT: Jacobian, // Tangent used for friction
    jB: Jacobian, // BiTangent used for friction

    lifetime: u8,
    id: u32, // Unique Identifier for each contact
};

const Jacobian = struct {
    // Omega to Quaternion instead from axis angle?
    Va: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 }, // Linear Velocity A
    Wa: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 }, // Angular Velocity A
    Vb: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 }, // Linear Velocity B
    Wb: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 }, // Angular Velocity B
    b: f32 = 0.0, // bias
    effective_mass: f32 = 0.0,
    total_lambda: f32 = 0.0,
}; // TODO type field????

pub const RenderContact = struct {
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

    // do a different order for integration
    euler_integration(bodies, delta_time);

    // Force Accumulation
    // Gravity
    // Bouyancy
    // Magnetism

    // Contact Generation

    // TODO remove collision type
    for (0..bodies.len) |i| {
        bodies[i].colliding = main.CollisionType.NONE;
    }

    // TODO implement 3D sweep and prune
    //const start_time = std.time.milliTimestamp();
    for (0..bodies.len) |a_index| {
        for ((a_index + 1)..bodies.len) |b_index| {
            if (a_index != b_index) {
                const a: *main.Object = &bodies[a_index];
                const b: *main.Object = &bodies[b_index];
                if (sphere_collision_test(a, b)) {
                    try generate_contacts(a, b, contacts);
                }
            }
        }
    }

    //for (0..contacts.items.len) |contact_index| {
    //    prepare_contact(&contacts.items[contact_index], delta_time);
    //}

    for (0..contacts.items.len) |contact_index| {
        const j = &contacts.items[contact_index].jN;
        init_jacobian(j, &contacts.items[contact_index], @as(f32, @floatCast(delta_time)));
    }

    pGS_contact_solver(contacts.items, delta_time);

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

        //contacts.clearRetainingCapacity();

        // resolve collisions (apply torques)
        //generate_impulses();
    }
}

// TODO replace with RK4?
/// Classical Mechanics: Basic Euler Integrator
pub fn euler_integration(objects: []main.Object, delta_time: f64) void {
    for (0..objects.len) |index| {
        if (objects[index].inverse_mass > 0.0) {
            objects[index].last_frame_acceleration = objects[index].acceleration;

            // We store this for later so we can use it in collision resolution
            const linear_acceleration: zm.Vec = cm.scale_f32(
                objects[index].force_accumulation,
                objects[index].inverse_mass,
            );

            objects[index].last_frame_acceleration += linear_acceleration;

            // Integrate velocity
            objects[index].velocity += cm.scale_f32(linear_acceleration, @as(f32, @floatCast(delta_time)));

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

            if (!objects[index].lock_pos) {
                // velocity integration
                objects[index].position += .{
                    objects[index].velocity[0] * delta_time,
                    objects[index].velocity[1] * delta_time,
                    objects[index].velocity[2] * delta_time,
                };
            }

            //const angular_velocity_normalized: zm.Vec = zm.normalize3(objects[index].angular_velocity);
            //const angular_velocity_length: f32 = zm.length3(objects[index].angular_velocity)[0];
            //// angular velocity integration

            if (!objects[index].lock_rot) {
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
            }

            // reset forces // TODO is this correct?
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
    // Cast should be ok as long as objects being compared are within
    // the f32 range. All internal calculations should be relative but they aren't...
    const ab_center_line: zm.Vec = cm.cast_position(ab_center_line_f128);

    var best_index: u32 = 100;
    var best_overlap: f32 = 10000.0;

    var are_penetrating: bool = false;

    // TODO optimize this a little more?
    // Box A axis'
    are_penetrating = try_axis(
        0,
        zm.normalize3(a.getXAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        1,
        zm.normalize3(a.getYAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        2,
        zm.normalize3(a.getZAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );

    // Box B axis'
    are_penetrating = are_penetrating and try_axis(
        3,
        zm.normalize3(b.getXAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        4,
        zm.normalize3(b.getYAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        5,
        zm.normalize3(b.getZAxis()),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );

    // MISC axis'
    are_penetrating = are_penetrating and try_axis(
        6,
        zm.normalize3(zm.cross3(a.getXAxis(), b.getXAxis())),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        7,
        zm.normalize3(zm.cross3(a.getXAxis(), b.getYAxis())),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        8,
        zm.normalize3(zm.cross3(a.getXAxis(), b.getZAxis())),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        9,
        zm.normalize3(zm.cross3(a.getYAxis(), b.getXAxis())),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        10,
        zm.normalize3(zm.cross3(a.getYAxis(), b.getYAxis())),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        11,
        zm.normalize3(zm.cross3(a.getYAxis(), b.getZAxis())),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        12,
        zm.normalize3(zm.cross3(a.getZAxis(), b.getXAxis())),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        13,
        zm.normalize3(zm.cross3(a.getZAxis(), b.getYAxis())),
        a,
        b,
        ab_center_line,
        &best_overlap,
        &best_index,
    );
    are_penetrating = are_penetrating and try_axis(
        14,
        zm.normalize3(zm.cross3(a.getZAxis(), b.getZAxis())),
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

    // std.debug.print("{}\n", .{best_overlap});

    if (are_penetrating) {
        // std.debug.print("penetrating", .{});
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
        } else if (best_index < 15) {
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

    const overlap: f32 = penetration_on_axis(
        a,
        b,
        axis,
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

/// Overlap of 2 spheres with a radius of the largest dimension of each box's half_size.
/// does not produce a contact
fn sphere_collision_test(
    a: *main.Object,
    b: *main.Object,
) bool {
    var result: bool = false;

    const a_length = zm.length3(a.half_size)[0];

    const b_length = zm.length3(a.half_size)[0];

    if (@abs(cm.distance_f128(a.position, b.position)) < a_length + b_length) {
        result = true;
    }

    return result;
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

/// Computes the contact data of 2 bodies given their interpenetration is between a mutual face and vertex.
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

    var vertexB: zm.Vec = b.half_size;
    // vertex of box 1 and face of box 2
    if (zm.dot3(b.getXAxis(), normal)[0] < 0.0) {
        vertexB[0] = -vertexB[0];
    }
    if (zm.dot3(b.getYAxis(), normal)[0] < 0.0) {
        vertexB[1] = -vertexB[1];
    }
    if (zm.dot3(b.getZAxis(), normal)[0] < 0.0) {
        vertexB[2] = -vertexB[2];
    }

    var vertexA: zm.Vec = b.half_size;
    // vertex of box 1 and face of box 2
    if (zm.dot3(a.getXAxis(), normal)[0] < 0.0) {
        vertexA[0] = -vertexA[0];
    }
    if (zm.dot3(a.getYAxis(), normal)[0] < 0.0) {
        vertexA[1] = -vertexA[1];
    }
    if (zm.dot3(a.getZAxis(), normal)[0] < 0.0) {
        vertexA[2] = -vertexA[2];
    }

    vertexA = zm.mul(a.transform(), vertexA);
    vertexB = zm.mul(b.transform(), vertexB);

    // TODO add materials for bocks and have the
    // friction and restitution derived from it
    //std.debug.print("generated penetration: {}\n", .{penetration});
    const contact: Contact = .{
        .lifetime = 0,
        .normal = -normal,
        .penetration = penetration,
        .jN = Jacobian{},
        .jB = Jacobian{},
        .jT = Jacobian{},
        .A = a,
        .B = b,
        .pA = vertexA,
        .pB = vertexB, // Use this one IG
        .rA = vertexA - cm.cast_position(a.position),
        .rB = vertexB - cm.cast_position(b.position),
        .id = 0,
    };

    list.appendAssumeCapacity(contact);
}

/// Computes the contact data of 2 bodies given their interpenetration is along 2 edges.
pub fn edge_edge_contact(
    list: *std.ArrayList(Contact),
    a: *main.Object,
    b: *main.Object,
    best_index: u32,
    penetration: f32,
    center_line: zm.Vec,
) void {
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

    const vertexA = zm.mul(a.transform(), vertex); // TODO make sure this is correct (it isn't)
    const vertexB = zm.mul(b.transform(), vertex); // TODO make sure this is correct (it isn't)

    const contact: Contact = .{
        .lifetime = 0,
        .normal = -axis,
        .penetration = penetration,
        //.positionA = zm.mul(b.transform(), vertex),
        .jN = Jacobian{},
        .jB = Jacobian{},
        .jT = Jacobian{},
        .A = a,
        .B = b,
        .pA = zm.mul(a.transform(), vertex), // TODO make sure this is correct (it isn't)
        .pB = zm.mul(b.transform(), vertex), // Use this one IG
        .rA = vertexA - cm.cast_position(a.position),
        .rB = vertexB - cm.cast_position(b.position),
        .id = 0,
    };

    list.appendAssumeCapacity(contact);
}

/// Finds the penetration depth of the given Boxes A and B on the provided axis
///
/// box_a: transformations pertaining to box a
/// box_b: transformation pertaining to box b
/// axis: the axis box_a and box_b will be projected onto to test whether they overlap or not
/// ab_center_line: the vector from the center of box_a to box_b in world coordinates
fn penetration_on_axis(
    a: *main.Object,
    b: *main.Object,
    axis: zm.Vec,
    ab_center_line: zm.Vec,
) f32 {
    const a_projection: f32 =
        a.half_size[0] * @abs(zm.dot3(a.getXAxis(), axis)[0]) +
        a.half_size[1] * @abs(zm.dot3(a.getYAxis(), axis)[0]) +
        a.half_size[2] * @abs(zm.dot3(a.getZAxis(), axis)[0]);

    const b_projection: f32 =
        b.half_size[0] * @abs(zm.dot3(b.getXAxis(), axis)[0]) +
        b.half_size[1] * @abs(zm.dot3(b.getYAxis(), axis)[0]) +
        b.half_size[2] * @abs(zm.dot3(b.getZAxis(), axis)[0]);

    const distance: f32 = @abs(zm.dot3(axis, ab_center_line)[0]);
    return a_projection + b_projection - distance;
}

/// Produces a Orthonormal basis to the provided normal vector
/// This does not work well with friction though
fn orthonormal_basis(contact_vec: zm.Vec) zm.Mat {
    var result: zm.Mat = zm.identity();
    var contact_cotangent: [2]zm.Vec = .{ .{ 0.0, 0.0, 0.0, 0.0 }, .{ 0.0, 0.0, 0.0, 0.0 } };

    if (@abs(contact_vec[0]) > @abs(contact_vec[1])) {
        const scale_factor = 1.0 / @sqrt(contact_vec[2] * contact_vec[2] + contact_vec[0] * contact_vec[0]);
        contact_cotangent[0] = .{
            contact_vec[2] * scale_factor,
            0.0,
            -contact_vec[0] * scale_factor,
            0.0,
        };

        contact_cotangent[1] = .{
            contact_vec[1] * contact_cotangent[0][0],
            contact_vec[2] * contact_cotangent[0][0] - contact_vec[0] * contact_cotangent[0][2],
            -contact_vec[1] * contact_cotangent[0][0],
            0.0,
        };
    } else {
        const scale_factor = 1.0 / @sqrt(contact_vec[2] * contact_vec[2] + contact_vec[1] * contact_vec[1]);
        contact_cotangent[0] = .{
            0.0,
            -contact_vec[2] * scale_factor,
            contact_vec[1] * scale_factor,
            0.0,
        };

        contact_cotangent[1] = .{
            contact_vec[1] * contact_cotangent[0][2] - contact_vec[2] * contact_cotangent[0][1],
            -contact_vec[0] * contact_cotangent[0][2],
            contact_vec[0] * contact_cotangent[0][1],
            0.0,
        };
    }

    result = .{
        .{ contact_vec[0], contact_cotangent[0][0], contact_cotangent[1][0], 0.0 },
        .{ contact_vec[1], contact_cotangent[0][1], contact_cotangent[1][1], 0.0 },
        .{ contact_vec[2], contact_cotangent[0][2], contact_cotangent[1][2], 0.0 },
        .{ 0.0, 0.0, 0.0, 0.0 },
    };
    return result;
}

/// All numbers associated with the jacobian that can be computed once are done here
fn init_jacobian(j: *Jacobian, contact: *Contact, delta_time: f32) void {
    j.Va = -contact.normal;
    j.Wa = -zm.cross3(contact.rA, contact.normal);
    j.Vb = contact.normal;
    j.Wb = zm.cross3(contact.rB, contact.normal);

    const transformA: zm.Mat = zm.mul(cm.scale_matrix(contact.A.half_size), zm.matFromQuat(contact.A.orientation));
    const transform_iitA = zm.mul(zm.mul(zm.transpose(transformA), contact.A.inverse_inertia_tensor), transformA);

    const transformB: zm.Mat = zm.mul(cm.scale_matrix(contact.B.half_size), zm.matFromQuat(contact.B.orientation));
    const transform_iitB = zm.mul(zm.mul(zm.transpose(transformB), contact.B.inverse_inertia_tensor), transformB);

    j.effective_mass = 1.0 / (contact.A.inverse_mass +
        zm.dot3(j.Wa, zm.mul(transform_iitA, j.Wa))[0] +
        contact.B.inverse_mass +
        zm.dot3(j.Wb, zm.mul(transform_iitB, j.Wb))[0]);

    const beta: f32 = 0.7 * 0.7;
    // restitution is the product of the 2 material resititutions, but we don't have a system for that rn
    const relative_velocity = -contact.A.velocity - zm.cross3(contact.A.angular_velocity, contact.rA) + contact.B.velocity + zm.cross3(contact.B.angular_velocity, contact.rB);
    //const relative_velocity = -contact.A.velocity + contact.B.velocity;
    const closing_velocity = zm.dot3(relative_velocity, contact.normal)[0];
    const restitution = contact.A.restitution * contact.B.restitution;
    j.b = -(beta / delta_time) * contact.penetration + (restitution * closing_velocity);
    // j.b = 0;

    j.total_lambda = 0.0;
}

// I'm trapped in this body and I must scream

/// Projected Gauss-Seidel Solver
/// Solve contact constraints via velocity
fn pGS_contact_solver(contacts: []Contact, delta_time: f64) void {
    _ = &delta_time;

    //const updated_velocity = struct {
    //    body_index: usize,
    //    delta_velocity: zm.Vec,
    //};

    //var velocities = std.ArrayList(updated_velocity).initCapacity(contacts.len * 2);

    // Calculate velocity changes for all collision constraints
    var violate: bool = true;
    var iteration: u32 = 0;
    // while (iteration < 2) {
    for (contacts, 0..contacts.len) |contact, contact_index| {
        _ = &contact_index;
        // Essentially we are solving for lambda
        // To do this we use GS to solve lambda = -J V_i * (J M^-1 J^T)^-1
        // In order for the constraint to become resoved JV + b >= 0 must be true

        //const m_ra = contact.position - cm.cast_position(contact.bodies[0].position);
        //const m_rb = contact.position - cm.cast_position(contact.bodies[1].position);
        //std.debug.print("{} {} {} {}\n", .{ ra, rb, m_ra, m_rb });

        //const jv_i = ;//Initial velocity
        //var jv_k = ;

        for (0..10) |i| {
            _ = &i;
            const j = &contact.jN;

            const jv: f32 =
                zm.dot3(j.Va, contact.A.velocity)[0] +
                zm.dot3(j.Wa, contact.A.angular_velocity)[0] +
                zm.dot3(j.Vb, contact.B.velocity)[0] +
                zm.dot3(j.Wb, contact.B.angular_velocity)[0];

            // Ax + b = 0 : (Gauss-Seidel solves for A) A = D -L -U
            // GS is used to solve for A, x is the impulse, b is the initial velocity/bias term
            // A = J M^-1 J^T, b = J Vi
            // x = A^-1 * -b

            var lambda: f32 = j.effective_mass * -(jv + j.b);
            const old_total_lambda = j.total_lambda;
            contacts[contact_index].jN.total_lambda = @max(0.0, j.total_lambda + lambda);
            // std.debug.print("fresh lambda: {} old lambda: {} new lambda: {} {}\n", .{ lambda, old_total_lambda, contacts[contact_index].jN.total_lambda, j.total_lambda });
            lambda = contacts[contact_index].jN.total_lambda - old_total_lambda;
            // std.debug.print("jv: {} eM: {} lambda: {}   \n", .{ jv, contact.jN.effective_mass, lambda });

            // const transformA: zm.Mat = zm.mul(cm.scale_matrix(contact.A.half_size), zm.matFromQuat(contact.A.orientation));
            // const transform_iitA = zm.mul(zm.mul(zm.transpose(transformA), contact.A.inverse_inertia_tensor), transformA);

            // const transformB: zm.Mat = zm.mul(cm.scale_matrix(contact.B.half_size), zm.matFromQuat(contact.B.orientation));
            // const transform_iitB = zm.mul(zm.mul(zm.transpose(transformB), contact.B.inverse_inertia_tensor), transformB);

            // TODO fix delta angular velocity
            contact.A.velocity += cm.scale_f32(j.Va, contact.A.inverse_mass * lambda);
            // contact.A.angular_velocity += cm.scale_f32(zm.mul(transform_iitA, j.Wa), lambda);
            contact.B.velocity += cm.scale_f32(j.Vb, contact.B.inverse_mass * lambda);
            // contact.B.angular_velocity += cm.scale_f32(zm.mul(transform_iitB, j.Wb), lambda);

            // if constraints converge
            // Velocity convergence can be defined by (-Va - (Wz X ra) + Vb + (Wb X rb)) . contact_normal >= 0
            // Position convergence can be defined by (Pb - Pa) . contact_normal >= 0 or by (Centerb + rb - Centera - ra) . contact_normal >= 0
            // Position constraints can be done with baumgart stabilization, but might not be necessary with
            // the particular paper we are following
            iteration += 1;
            _ = &violate;
        }
    }
    // }

    //for (contacts, 0..contacts.len) |contact, contact_index| {
    //    _ = &velocities;
    //    _ = &contact;
    //    _ = &solve_iteration;
    //    _ = &contact_index;
    //}

    // Update the velocities of all bodies involved in the constraints
}

fn GR_solve(contacts: []Contact, delta_time: f64) void {
    _ = &contacts;
    _ = &delta_time;
}

/// Temporal Gauss-Seidel Solver
fn tGS_solve(contacts: []Contact, delta_time: f64) void {
    _ = &contacts;
    _ = &delta_time;
}

/// Extended Position-Based Dynamics Solver
fn XPBD_solve(contacts: []Contact, delta_time: f64) void {
    _ = &contacts;
    _ = &delta_time;
}
