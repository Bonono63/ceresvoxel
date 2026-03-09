//! Physics simulation runtime and data structures
//! Most of this code is derived from Cyclone Engine by Ian Millington
//! licensed under the MIT license.
const std = @import("std");
const zm = @import("zmath");
const cm = @import("ceresmath.zig");
const chunk = @import("chunk.zig");
const main = @import("main.zig");
const gGS = @import("gGS.zig");

pub const GRAVITATIONAL_CONSTANT: f128 = 6.67428e-11;
pub const AU: f128 = 149.6e9;
pub const SCALE: f32 = 50.0;

const MAX_CONTACT_LIFETIME: u32 = 4;
const MAX_VELOCITY_PER_FRAME: f32 = 0.25;

pub const Contact = struct {
    bodies: [2]*main.Object,
    penetration: f32,
    restitution: f32, // how close to ellastic vs inellastic
    friction: f32,
    position: zm.Vec, // this needs to be @Vector(3, f128)
    normal: zm.Vec,
    basis: zm.Mat = zm.identity(),
    transform: zm.Mat = zm.identity(),
    desired_velocity: f32 = 0.0,
    /// stored this way for easier comparisons during resolution
    relative_contact_position: [2]zm.Vec,
    velocity: zm.Vec, // contactVelocity
    lifetime: u8,
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

    for (0..contacts.items.len) |contact_index| {
        prepare_contact(&contacts.items[contact_index], delta_time);
    }

    //gGS_resolve_collisions(contacts.items, delta_time);

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

// TODO replace with RK4
/// Classical Mechanics: Basic Euler Integrator
pub fn integration(objects: []main.Object, delta_time: f64) void {
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

    // TODO make all of these switch statements
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
    //std.debug.print("generated penetration: {}\n", .{penetration});
    const contact: Contact = .{
        .lifetime = 0,
        .normal = normal,
        .penetration = penetration,
        .position = zm.mul(b.transform(), vertex),
        .restitution = 0.2,
        .friction = 0.1,
        .bodies = .{ a, b },
        .relative_contact_position = .{ .{ 0.0, 0.0, 0.0, 0.0 }, .{ 0.0, 0.0, 0.0, 0.0 } },
        .velocity = .{ 0.0, 0.0, 0.0, 0.0 },
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
        .lifetime = 0,
        .normal = axis,
        .penetration = penetration,
        .position = vertex,
        .restitution = 0.2,
        .friction = 0.1,
        .bodies = .{ a, b },
        .relative_contact_position = .{ .{ 0.0, 0.0, 0.0, 0.0 }, .{ 0.0, 0.0, 0.0, 0.0 } },
        .velocity = .{ 0.0, 0.0, 0.0, 0.0 },
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

/// Compute various necessary values to be used throughout collision resolution
fn prepare_contact(
    contact: *Contact,
    delta_time: f64,
) void {
    contact.basis = orthonormal_basis(contact.normal);
    const a_cast_pos: zm.Vec = .{
        @as(f32, @floatCast(contact.bodies[0].position[0])),
        @as(f32, @floatCast(contact.bodies[0].position[1])),
        @as(f32, @floatCast(contact.bodies[0].position[2])),
        0.0,
    };
    const b_cast_pos: zm.Vec = .{
        @as(f32, @floatCast(contact.bodies[1].position[0])),
        @as(f32, @floatCast(contact.bodies[1].position[1])),
        @as(f32, @floatCast(contact.bodies[1].position[2])),
        0.0,
    };
    const relative_contact_position_a: zm.Vec = contact.position - a_cast_pos;
    const relative_contact_position_b: zm.Vec = contact.position - b_cast_pos;
    contact.relative_contact_position = .{ relative_contact_position_a, relative_contact_position_b };

    // Do we need the contact velocity saved for later?
    contact.velocity = calculate_local_velocity(contact, contact.bodies[0], relative_contact_position_a, delta_time);
    contact.velocity -= calculate_local_velocity(contact, contact.bodies[1], relative_contact_position_b, delta_time);

    contact.desired_velocity = calculate_desired_velocity(contact, contact.velocity, delta_time);
}

/// Top level implementation of an iterative physics solver
fn cyclone_resolve_collisions(
    contacts: *std.ArrayListUnmanaged(Contact),
    delta_time: f64,
) void {
    adjust_body_position(contacts.items, delta_time);
    adjust_velocities(contacts.items, delta_time);
}

/// Calculates the velocity change of the given body according to the contact
/// provided
fn calculate_local_velocity(
    contact: *Contact,
    object: *main.Object,
    contact_relative_position: zm.Vec,
    delta_time: f64,
) zm.Vec {
    const ctwt = contact_to_world_transpose(contact);

    var velocity: zm.Vec = zm.cross3(object.orientation, contact_relative_position);
    velocity += object.velocity;

    var contact_velocity = zm.mul(ctwt, velocity);

    var acceleration_velocity = cm.scale_f32(object.last_frame_acceleration, @as(f32, @floatCast(delta_time)));
    acceleration_velocity = zm.mul(ctwt, acceleration_velocity);
    acceleration_velocity[0] = 0.0; // ignore acceleration in the x direction since that is the normal direction

    contact_velocity += acceleration_velocity;

    return contact_velocity;
}

/// Produced the dresired velocity of the collision along the collision normal of the Contact
fn calculate_desired_velocity(
    contact: *Contact,
    contact_velocity: zm.Vec,
    delta_time: f64,
) f32 {
    var result: f32 = 0.0;

    var velocity_from_acceleration: f32 = 0.0;

    velocity_from_acceleration += zm.dot3(contact.bodies[0].last_frame_acceleration, contact.normal)[0] * @as(f32, @floatCast(delta_time));
    velocity_from_acceleration += zm.dot3(contact.bodies[1].last_frame_acceleration, contact.normal)[0] * @as(f32, @floatCast(delta_time));

    var restitution: f32 = contact.restitution;
    if (@abs(contact_velocity[0]) < MAX_VELOCITY_PER_FRAME) { // This is really MAX VELOCITY PER STEP, but whatever
        restitution = 0.0;
    }

    result = -contact_velocity[0] - restitution * (contact_velocity[0] - velocity_from_acceleration);

    return result;
}

fn adjust_body_position(
    contacts: []Contact,
    delta_time: f64,
) void {
    _ = &delta_time;
    const MAX_ADJUSTMENT_ITERATIONS = 200;

    var iteration_count: usize = 0;
    while (iteration_count < MAX_ADJUSTMENT_ITERATIONS) {
        // Sort through all contacts to find the largest penetration
        var max: f32 = 0.1;
        var max_index: usize = contacts.len;
        for (contacts, 0..contacts.len) |_contact, contact_index| {
            if (_contact.penetration > max) {
                max = _contact.penetration;
                max_index = contact_index;
            }
        }
        if (max_index == contacts.len) {
            break;
        }
        std.debug.print("{}\n", .{max});

        // something something awake state...

        // resolve the penetration
        var linear_change: [2]zm.Vec = .{ .{ 0.0, 0.0, 0.0, 0.0 }, .{ 0.0, 0.0, 0.0, 0.0 } };
        var angular_change: [2]zm.Vec = .{ .{ 0.0, 0.0, 0.0, 0.0 }, .{ 0.0, 0.0, 0.0, 0.0 } };
        apply_position_change(
            &contacts[max_index],
            &linear_change,
            &angular_change,
            max,
        );

        //std.debug.print("{} {} {} {}\n", .{ angular_change[0], linear_change[0], angular_change[1], linear_change[1] });

        //Update the penetration of each body involved in the contact
        for (0..contacts.len) |contact_index| {
            for (0..2) |a| {
                for (0..2) |b| {
                    if (contacts[contact_index].bodies[a] == contacts[max_index].bodies[b]) {
                        const delta_position: zm.Vec = linear_change[b] + cm.vector_product(
                            angular_change[b],
                            contacts[contact_index].relative_contact_position[a],
                        );

                        contacts[contact_index].penetration += cm.scalar_product(delta_position, contacts[contact_index].normal) * @as(f32, if (a == 0) 1.0 else -1.0);
                    }
                }
            }
        }
        iteration_count += 1;
    }
}

/// Linear Projection
fn apply_position_change(
    contact: *Contact,
    linear_change: *[2]zm.Vec,
    angular_change: *[2]zm.Vec,
    penetration: f32,
) void {
    const angular_rotation_limit: f32 = 0.2;

    var total_inertia: f32 = 0.0;
    var linear_inertia: [2]f32 = .{ 0.0, 0.0 };
    var angular_inertia: [2]f32 = .{ 0.0, 0.0 };

    // Find Inertia in contact normal direction
    for (0..2) |body_index| {
        const body: *main.Object = contact.bodies[body_index];
        const inverse_inertia_tensor: zm.Mat = body.inverse_inertia_tensor; // TODO maybe make this a pointer?

        var angular_inertia_world: zm.Vec = zm.cross3(contact.relative_contact_position[body_index], contact.normal);
        angular_inertia_world = zm.mul(inverse_inertia_tensor, angular_inertia_world);
        angular_inertia_world = zm.cross3(angular_inertia_world, contact.relative_contact_position[body_index]);

        angular_inertia[body_index] = zm.dot3(angular_inertia_world, contact.normal)[0];

        linear_inertia[body_index] = body.inverse_mass;

        total_inertia += linear_inertia[body_index] + angular_inertia[body_index];
    }

    // calculate and apply changes

    for (0..2) |body_index| {
        const sign: f32 = if (body_index == 0) 1.0 else -1.0;
        var angular_move: f32 = sign * penetration * (angular_inertia[body_index] / total_inertia);
        var linear_move: f32 = sign * penetration * (linear_inertia[body_index] / total_inertia);

        // Limit angular rotations
        var projection: zm.Vec = contact.relative_contact_position[body_index];
        // scalar product (not dot product)
        const scalar: f32 = -cm.scalar_product(contact.relative_contact_position[body_index], contact.normal);
        projection += cm.scale_f32(contact.normal, scalar);

        const max_magnitude: f32 = angular_rotation_limit * zm.length3(projection)[0];

        const total_move = angular_move + linear_move;

        if (angular_move < -max_magnitude) {
            angular_move = -max_magnitude;
        } else if (angular_move > max_magnitude) {
            angular_move = max_magnitude;
        }

        linear_move = total_move - angular_move;

        if (angular_move == 0) // is this even possible???
        {
            angular_change[body_index] = .{ 0.0, 0.0, 0.0, 0.0 };
        } else {
            const target_angular_direction: zm.Vec = cm.vector_product(contact.relative_contact_position[body_index], contact.normal);
            angular_change[body_index] = cm.scale_f32(zm.mul(target_angular_direction, contact.bodies[body_index].inverse_inertia_tensor), (angular_move / angular_inertia[body_index]));
        }

        linear_change[body_index] = -cm.scale_f32(contact.normal, linear_move);

        //apply linear change
        const pos_change: @Vector(3, f128) = .{
            @as(f128, @floatCast(contact.normal[0] * linear_move)),
            @as(f128, @floatCast(contact.normal[1] * linear_move)),
            @as(f128, @floatCast(contact.normal[2] * linear_move)),
        };
        // std.debug.print("current pos: {}\n", .{contact.bodies[body_index].position});
        // std.debug.print("penetration for collision: {}\n", .{penetration});
        // std.debug.print("linear move for collision: {}\n", .{linear_move});
        // std.debug.print("pos change from collision: {}\n", .{pos_change});
        contact.bodies[body_index].position += pos_change;

        //apply angular change
        contact.bodies[body_index].orientation -= angular_change[body_index];
    }
}

fn adjust_velocities(
    contacts: []Contact,
    delta_time: f64,
) void {
    const MAX_VELOCITY_ITERATIONS_PER_FRAME = 100;
    var velocity_iterations: usize = 0;
    while (velocity_iterations < MAX_VELOCITY_ITERATIONS_PER_FRAME) {
        var velocity_change: [2]zm.Vec = .{ .{ 0.0, 0.0, 0.0, 0.0 }, .{ 0.0, 0.0, 0.0, 0.0 } };
        var rotation_change: [2]zm.Vec = .{ .{ 0.0, 0.0, 0.0, 0.0 }, .{ 0.0, 0.0, 0.0, 0.0 } };

        const VELOCITY_EPSILON: f32 = 0.1;
        var max: f32 = VELOCITY_EPSILON;
        var max_index: usize = 0;
        for (contacts, 0..contacts.len) |contact, contact_index| {
            if (contact.desired_velocity > max) {
                max = contact.desired_velocity;
                max_index = contact_index;
            }
        }
        if (max_index == contacts.len) {
            break;
        }

        apply_velocity_change(&contacts[max_index], &velocity_change, &rotation_change);

        // Update the velocity of the bodies associated with the contact for the next iteration
        for (0..contacts.len) |contact_index| {
            for (0..2) |a| {
                for (0..2) |b| {
                    if (contacts[contact_index].bodies[a] == contacts[max_index].bodies[b]) {
                        const delta_velocity = velocity_change[b] + cm.vector_product(
                            rotation_change[b],
                            contacts[contact_index].relative_contact_position[a],
                        );

                        const transformed_delta_velocity: zm.Vec = zm.mul(zm.mul(zm.translationV(contacts[contact_index].position), delta_velocity), zm.transpose(contacts[contact_index].basis));
                        contacts[contact_index].velocity += cm.scale_f32(transformed_delta_velocity, if (a == 0) -1.0 else 1.0);
                        contacts[contact_index].desired_velocity = calculate_desired_velocity(&contacts[contact_index], contacts[contact_index].velocity, delta_time);
                    }
                }
            }
        }
        velocity_iterations += 1;
    }
    //std.debug.print("adjust velocity iterations: {}\n", .{velocity_iterations});
}

fn apply_velocity_change(
    contact: *Contact,
    velocity_change: *[2]zm.Vec,
    rotation_change: *[2]zm.Vec,
) void {
    const impulse_contact: zm.Vec = calculate_frictionless_impulse(
        contact,
        .{
            contact.bodies[0].inverse_inertia_tensor,
            contact.bodies[1].inverse_inertia_tensor,
        },
    );

    //std.debug.print("impulse contact{} \n", .{impulse_contact});

    const impulse: zm.Vec = zm.mul(contact_to_world(contact), impulse_contact);

    const impulse_torque_a: zm.Vec = zm.cross3(contact.relative_contact_position[0], impulse);
    rotation_change[0] = zm.mul(contact.bodies[0].inverse_inertia_tensor, impulse_torque_a);
    velocity_change[0] = cm.scale_f32(impulse, contact.bodies[0].inverse_mass);

    // contact.bodies[0].velocity += velocity_change[0];
    // contact.bodies[0].orientation += rotation_change[0];

    const impulse_torque_b: zm.Vec = zm.cross3(impulse, contact.relative_contact_position[1]);
    rotation_change[1] = zm.mul(contact.bodies[1].inverse_inertia_tensor, impulse_torque_b);
    velocity_change[1] = cm.scale_f32(impulse, -contact.bodies[1].inverse_mass);

    // contact.bodies[1].velocity += velocity_change[1];
    // contact.bodies[1].orientation += rotation_change[1];
    //std.debug.print("velocity change: {} {} \n", .{ velocity_change[0], velocity_change[1] });
}

fn calculate_frictionless_impulse(
    contact: *Contact,
    inverse_inertia_tensor: [2]zm.Mat,
) zm.Vec {
    var impulse_contact: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 };

    var delta_velocity_world: zm.Vec = zm.cross3(contact.relative_contact_position[0], contact.normal);
    delta_velocity_world = zm.mul(inverse_inertia_tensor[0], delta_velocity_world);
    delta_velocity_world = zm.cross3(delta_velocity_world, contact.relative_contact_position[0]);

    var delta_velocity: f32 = zm.dot3(delta_velocity_world, contact.normal)[0];
    delta_velocity += contact.bodies[0].inverse_mass;

    delta_velocity_world = zm.cross3(contact.relative_contact_position[1], contact.normal);
    delta_velocity_world = zm.mul(inverse_inertia_tensor[1], delta_velocity_world);
    delta_velocity_world = zm.cross3(delta_velocity_world, contact.relative_contact_position[1]);

    delta_velocity += zm.dot3(delta_velocity_world, contact.normal)[0];

    delta_velocity += contact.bodies[1].inverse_mass;

    impulse_contact[0] = contact.desired_velocity / delta_velocity;
    impulse_contact[1] = 0.0;
    impulse_contact[2] = 0.0;

    return impulse_contact;
}

fn contact_to_world(contact: *Contact) zm.Mat {
    var result: zm.Mat = zm.identity();

    result = zm.translationV(contact.position);
    result = zm.mul(result, contact.basis);

    return result;
}

fn contact_to_world_transpose(contact: *Contact) zm.Mat {
    var result: zm.Mat = zm.identity();

    result = zm.translationV(contact.position);
    result = zm.mul(result, zm.transpose(contact.basis));

    return result;
}

/// Projected Gauss-Seidel Solver
fn pGS_solve(contacts: []Contact, delta_time: f64) void {
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
