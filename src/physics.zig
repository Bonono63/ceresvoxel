//!Physics simulation runtime and data structures
const std = @import("std");
const zm = @import("zmath");
const cm = @import("ceresmath.zig");
const chunk = @import("chunk.zig");
const main = @import("main.zig");

pub const GRAVITATIONAL_CONSTANT: f128 = 6.67428e-11;
pub const AU: f128 = 149.6e9;
pub const SCALE: f32 = 50.0;

pub const Body = struct {
    ///This should be sufficient for space exploration at a solar system level
    position: @Vector(3, f128),
    ///There is phyicsally no reason to be able to go above a speed or acceleration of 2.4 billion meters a second
    velocity: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, // meters per second
    // TODO decide whether a f32 is sufficient precision for mass calculations
    inverse_mass: f32,
    ///Sum accelerations of the forces acting on the particle
    force_accumulation: zm.Vec = .{0.0, 0.0, 0.0, 0.0},
    ///Helps with simulation stability, but for space it doesn't make much sense
    linear_damping: f32 = 0.99999,

    gravity: bool = true,
    planet: bool = false,
    orbit_radius: f128 = 0.0,
    barocenter: @Vector(3, f128) = .{0.0,0.0,0.0}, // center of the object's orbit
    eccentricity: f32 = 1.0,
    eccliptic_offset: @Vector(2, f32) = .{0.0, 0.0},

    orientation: zm.Quat = zm.qidentity(),
    angular_velocity: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, // axis-angle representation
    angular_damping: f32 = 0.99999,
    transform: zm.Mat = zm.identity(), // Current body transform, can be used for rendering as well
    inverse_inertia_tensor: zm.Mat = zm.inverse(zm.identity()),
    torque_accumulation: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, //change in axis is based on direction, strength the the coefficient from if it was a unit vector

    ///Collisions are only possible with boxes (other shapes can be added, but I can't be bothered)
    ///Make sure to only ever put in half the length of each dimension of the collision box
    half_size: zm.Vec,
};

const PlanetaryMotionStyle = enum {
    DETERMINISTIC,
    NONDETERMINISTIC,
};

pub const Contact = struct {
    position: zm.Vec,
    normal: zm.Vec,
    penetration: f32,
    restitution: f32, // how close to ellastic vs inellastic
    friction: f32,
};

// TODO maybe planets belong in a different array or structure, but for now they are the same
pub const PhysicsState = struct {
    bodies: std.ArrayList(Body),
    broad_contact_list: std.ArrayList([2]*Body),
    sim_start_time: i64,

    // Copies the current bodies to a double buffer and swaps between the two for the most recent data
    // Should only ever be used for reads
    display_bodies: [2][]Body = undefined,
    display_index: u32 = 0,
    copying: bool = false,

    mutex: std.Thread.Mutex = std.Thread.Mutex{},
    motion_style: PlanetaryMotionStyle = PlanetaryMotionStyle.DETERMINISTIC,
};

/// Integrates all linear forces, torques, angular velocities, linear velocities, positions, and orientations for the physics objects in the simulation
///
/// delta_time: the time in milliseconds since the last physics_tick call
/// sim_start_time: the first time the simulation was started (Created on world start) (UNIX time stamp)
/// sun_index: the index of the sun in @bodies
/// bodies: the bodies to be simulated over
pub fn physics_tick(delta_time: f64, sim_start_time: i64, bodies: []Body, contacts: *std.ArrayList(Contact)) void {
    // Planetary Motion
    for (0..bodies.len) |index| {
        if (bodies[index].planet) {
            // TODO make the orbit have an offset according to the barocenter
            // TODO Use eccentricity to skew one axis (x or z), the barocenter will have to be adjusted for more accurate
            // deterministic motion
            const time = @as(f64, @floatFromInt(std.time.milliTimestamp() - sim_start_time));
            const x: f128 = bodies[index].orbit_radius * @cos(time / bodies[index].orbit_radius / bodies[index].orbit_radius);
            const z: f128 = bodies[index].orbit_radius * @sin(time / bodies[index].orbit_radius / bodies[index].orbit_radius);
            const y: f128 = bodies[index].eccliptic_offset[0] * x + bodies[index].eccliptic_offset[1] * z;

            bodies[index].position = .{x,y,z};
        }
    }

    // Gravity
    // Bouyancy
    // Magnetism

    // Contact Generation

    // TODO implement 3D sweep and prune as a broad phase
    const start_time = std.time.milliTimestamp();
    for (0..bodies.len) |a| {
        for ((a+1)..bodies.len) |b| {
            if (a != b) {
                if (cm.distance_f128(bodies[a].position, bodies[b].position) < 2.0) {
                    //try generate_contacts(&bodies[a], &bodies[b], contacts);
                }
            }
        }
    }

    for (contacts.items) |contact| {
        _ = &contact;
        // resolve collisions (apply torques)
    }
    contacts.clearRetainingCapacity();
    // clear contacts

    std.debug.print("{}ms\n", .{std.time.milliTimestamp() - start_time});

    // Classical Mechanics (Integrator) 
    for (0..bodies.len) |index| {
        if (bodies[index].inverse_mass > 0.0) {
            // linear acceleration integration
            const resulting_linear_acceleration = cm.scale_f32(bodies[index].force_accumulation, bodies[index].inverse_mass * @as(f32, @floatCast(delta_time)));
            bodies[index].velocity += .{
                resulting_linear_acceleration[0],
                resulting_linear_acceleration[1],
                resulting_linear_acceleration[2],
                0.0,
            };

            const resulting_angular_acceleration: zm.Vec = zm.mul(bodies[index].inverse_inertia_tensor, bodies[index].torque_accumulation);
            bodies[index].angular_velocity += cm.scale_f32(resulting_angular_acceleration, @as(f32, @floatCast(delta_time)));

            // linear damping
            bodies[index].velocity = cm.scale_f32(bodies[index].velocity, bodies[index].linear_damping);
            
            // angular damping
            bodies[index].angular_velocity = cm.scale_f32(bodies[index].angular_velocity, bodies[index].angular_damping);

            // velocity integration
            bodies[index].position += .{
                bodies[index].velocity[0] * delta_time,
                bodies[index].velocity[1] * delta_time,
                bodies[index].velocity[2] * delta_time,
            };

            // angular velocity integration
            cm.q_add_vector(&bodies[index].orientation, .{
                    bodies[index].angular_velocity[0] * @as(f32, @floatCast(delta_time)),
                    bodies[index].angular_velocity[1] * @as(f32, @floatCast(delta_time)),
                    bodies[index].angular_velocity[2] * @as(f32, @floatCast(delta_time)),
                    0,
            });

            // calculate cached data
            bodies[index].orientation = cm.qnormalize(bodies[index].orientation);

            //std.debug.print("q: {any} omega: {any} t: {any}\n", .{bodies[index].orientation, bodies[index].angular_velocity, bodies[index].torque_accumulation});

            // reset forces
            bodies[index].force_accumulation = .{0.0, 0.0, 0.0, 0.0};
            bodies[index].torque_accumulation = .{0.0, 0.0, 0.0, 0.0};
        }
    }
}

/// produces a set of contacts between 2 bodies (boxes)
/// Up to 15 contacts per resolution
///
/// 
fn generate_contacts(a: *Body, b: *Body, contacts: *std.ArrayList(Contact)) u32 {
    _ = &contacts;
    var contact_count: u32 = 0;
    _ = &contact_count;

    var smallest_overlap_axis_index: u32 = 0;
    var smallest_overlap: f32 = 10000.0;
    for (0..15) |i| {
        var axis: zm.Vec = .{1.0, 0.0, 0.0, 0.0};
        switch (i) {
            0 => {
                axis = zm.mul(.{1.0, 0.0, 0.0, 0.0}, zm.matFromQuat(a.*.orientation));
            },
            1 => {
                axis = zm.mul(.{0.0, 1.0, 0.0, 0.0}, zm.matFromQuat(a.*.orientation));
            },
            2 => {
                axis = zm.mul(.{0.0, 0.0, 1.0, 0.0}, zm.matFromQuat(a.*.orientation));
            },
            else => {
            },
        }

        const ab_center_line_f128 = a.*.position - b.*.position;
        // this cast should be safe since the 2 bodies should be close enough for it to not be a problem
        const ab_center_line: zm.Vec = .{
            @as(f32, @floatCast(ab_center_line_f128[0])),
            @as(f32, @floatCast(ab_center_line_f128[1])),
            @as(f32, @floatCast(ab_center_line_f128[2])),
            0.0,
        };
       
        const a_transform: zm.Mat = zm.mul(a.*.half_size, zm.matFromQuat(a.*.orientation));
        const b_transform: zm.Mat = zm.mul(b.*.half_size, zm.matFromQuat(b.*.orientation));
        const overlap: f32 = penetration_on_axis(a.*.half_size, a_transform, b.*.half_size, b_transform, axis, ab_center_line);
        
        if (overlap < 0) {} // TODO break out of loop
        if (overlap < smallest_overlap) {
            smallest_overlap = overlap;
            smallest_overlap_axis_index = i;
        }
    }

    return contact_count;
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
fn penetration_on_axis(box_a: zm.Vec, transform_a: zm.Mat, box_b: zm.Vec, transform_b: zm.Mat, axis: zm.Vec, ab_center_line: zm.Vec) f32 {
    const a_axis = zm.mul(transform_a, box_a);
    const b_axis = zm.mul(transform_b, box_b);

    const a_projected = cm.projectV(a_axis, axis);
    const b_projected = cm.projectV(b_axis, axis);

    const a_projected_length: f32 = zm.length3(a_projected);
    const b_projected_length: f32 = zm.length3(b_projected);

    const distance: f32 = zm.length3(cm.projectV(axis, ab_center_line));
    
    return a_projected_length + b_projected_length - distance;
}
