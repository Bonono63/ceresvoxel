//!Physics simulation runtime and data structures
const std = @import("std");
const zm = @import("zmath");
const cm = @import("ceresmath.zig");
const chunk = @import("chunk.zig");
const main = @import("main.zig");

pub const GRAVITATIONAL_CONSTANT: f128 = 6.67428e-11;
pub const AU: f128 = 149.6e9;
pub const SCALE: f32 = 50.0;

const BodyType = enum {
    voxel_space,
    particle,
    player,
    other,
};

pub const Body = struct {
    ///This should be sufficient for space exploration at a solar system level
    position: @Vector(3, f128),
    ///There is phyicsally no reason to be able to go above a speed
    ///or acceleration of 2.4 billion meters a second
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
    /// center of the object's orbit
    barocenter: @Vector(3, f128) = .{0.0,0.0,0.0},
    eccentricity: f32 = 1.0,
    eccliptic_offset: @Vector(2, f32) = .{0.0, 0.0},

    orientation: zm.Quat = zm.qidentity(),
    /// axis-angle representation
    angular_velocity: zm.Vec = .{0.0, 0.0, 0.0, 0.0},
    /// factor for reducing the angular velocity every tick
    angular_damping: f32 = 0.99999,
    inverse_inertia_tensor: zm.Mat = zm.inverse(zm.identity()),
    ///change in axis is based on direction,
    ///strength the the coefficient from if it was a unit vector
    torque_accumulation: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, 
    ///Collisions are only possible with boxes (other shapes can be added, but I can't be bothered)
    ///Make sure to only ever put in half the length of each dimension of the collision box
    half_size: zm.Vec,
   
    body_type: BodyType,
    particle_time: u32 = 0,

    /// Returns the object's transform (for rendering or physics)
    /// for safety reasons should only be called on objects within f32's range.
    pub fn transform(self: *const Body) zm.Mat {
        const center: zm.Vec = cm.scale_f32(self.half_size, -1.0);
        const world_pos: zm.Mat = zm.translationV(.{
                @as(f32, @floatCast(self.position[0])),
                @as(f32, @floatCast(self.position[1])),
                @as(f32, @floatCast(self.position[2])),
                0.0,
            });
        var result: zm.Mat = zm.identity();
        result = zm.mul(zm.matFromQuat(self.orientation), zm.translationV(center));
        return zm.mul(result, world_pos);
    }

    /// Returns the X axis given the body's current transform 
    pub fn getXAxis(self: *const Body) zm.Vec {
        return zm.mul(self.transform(), zm.Vec{1.0,0.0,0.0,0.0});
    }

    /// Returns the Y axis given the body's current transform 
    pub fn getYAxis(self: *const Body) zm.Vec {
        return zm.mul(self.transform(), zm.Vec{0.0,1.0,0.0,0.0});
    }
    
    /// Returns the Z axis given the body's current transform 
    pub fn getZAxis(self: *const Body) zm.Vec {
        return zm.mul(self.transform(), zm.Vec{0.0,0.0,1.0,0.0});
    }
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
    //broad_contact_list: std.ArrayList([2]*Body),
    sim_start_time: i64,

    //Copies the current bodies to a double buffer and swaps between the two for the most recent data
    //Should only ever be used for reads
    display_bodies: [2][]Body = undefined,
    display_index: u32 = 0,
    copying: bool = false,

    mutex: std.Thread.Mutex = std.Thread.Mutex{},
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
    bodies: []Body,
    contacts: *std.ArrayList(Contact)
    ) !void {
    // Planetary Motion
    for (0..bodies.len) |index| {
        if (bodies[index].planet) {
            // TODO make the orbit have an offset according to the barocenter
            // TODO Use eccentricity to skew one axis (x or z), the barocenter will have to be adjusted for more accurate
            // deterministic motion
            const time = @as(f64, @floatFromInt(std.time.milliTimestamp() - sim_start_time));
            const x: f128 = bodies[index].orbit_radius
                * @cos(time / bodies[index].orbit_radius / bodies[index].orbit_radius);
            const z: f128 = bodies[index].orbit_radius
                * @sin(time / bodies[index].orbit_radius / bodies[index].orbit_radius);
            const y: f128 = bodies[index].eccliptic_offset[0]
                * x + bodies[index].eccliptic_offset[1] * z;

            bodies[index].position = .{x,y,z};
        }
    }

    // Gravity
    // Bouyancy
    // Magnetism

    // Contact Generation

    // TODO implement 3D sweep and prune as a broad phase
    //const start_time = std.time.milliTimestamp();
    for (0..bodies.len) |a| {
        for ((a+1)..bodies.len) |b| {
            if (a != b) {
                if (cm.distance_f128(bodies[a].position, bodies[b].position) < 2.0) {
                    try generate_contacts(&bodies[a], &bodies[b], contacts);
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

    //std.debug.print("{}ms\n", .{std.time.milliTimestamp() - start_time});

    // Classical Mechanics (Integrator) 
    for (0..bodies.len) |index| {
        if (bodies[index].inverse_mass > 0.0) {
            // linear acceleration integration
            const resulting_linear_acceleration = cm.scale_f32(
                bodies[index].force_accumulation,
                bodies[index].inverse_mass * @as(f32, @floatCast(delta_time))
                );

            bodies[index].velocity += .{
                resulting_linear_acceleration[0],
                resulting_linear_acceleration[1],
                resulting_linear_acceleration[2],
                0.0,
            };

            const resulting_angular_acceleration: zm.Vec = zm.mul(
                bodies[index].inverse_inertia_tensor,
                bodies[index].torque_accumulation
                );

            bodies[index].angular_velocity += cm.scale_f32(
                resulting_angular_acceleration,
                @as(f32, @floatCast(delta_time))
                );

            // linear damping
            bodies[index].velocity = cm.scale_f32(
                bodies[index].velocity,
                bodies[index].linear_damping
                );
            
            // angular damping
            bodies[index].angular_velocity = cm.scale_f32(
                bodies[index].angular_velocity,
                bodies[index].angular_damping
                );

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
fn generate_contacts(a: *Body, b: *Body, contacts: *std.ArrayList(Contact)) !void {
    _ = &contacts;

    const ab_center_line_f128 = a.*.position - b.*.position;
    // this cast should be safe since the 2 bodies should be close enough for it to not be a problem
    const ab_center_line: zm.Vec = .{
        @as(f32, @floatCast(ab_center_line_f128[0])),
        @as(f32, @floatCast(ab_center_line_f128[1])),
        @as(f32, @floatCast(ab_center_line_f128[2])),
        0.0,
    };
    
    var smallest_overlap_axis_index: u32 = 0;
    var smallest_overlap: f32 = 10000.0;
    for (0..14) |i| {
        var axis: zm.Vec = SAT_axis(@intCast(i), a, b);

        if (zm.lengthSq3(axis)[0] > 0.001) {
            axis = zm.normalize3(axis);
           
            const a_transform: zm.Mat = zm.matFromQuat(a.*.orientation);
            const b_transform: zm.Mat = zm.matFromQuat(b.*.orientation);
            const overlap: f32 = penetration_on_axis(
                a.*.half_size,
                a_transform,
                b.*.half_size,
                b_transform,
                axis,
                ab_center_line
                );
            
            if (overlap < 0) { return; }
            if (overlap < smallest_overlap) {
                smallest_overlap = overlap;
                smallest_overlap_axis_index = @intCast(i);
            }
        }
    }

    const axis: zm.Vec = SAT_axis(smallest_overlap_axis_index, a, b);
    var normal = axis;

    // Correct normal direction 
    if (zm.dot3(normal, ab_center_line)[0] > 0.0) {
        normal = cm.scale_f32(normal, -1.0);
    }

    var vertex: zm.Vec = b.half_size;
    if (zm.dot3(b.getXAxis(), normal)[0] < 0.0) {
        vertex[0] = -vertex[0];
    }
    if (zm.dot3(b.getYAxis(), normal)[0] < 0.0) {
        vertex[1] = -vertex[1];
    }
    if (zm.dot3(b.getZAxis(), normal)[0] < 0.0) {
        vertex[2] = -vertex[2];
    }

    const contact: Contact = .{
        .normal = axis,
        .penetration = smallest_overlap,
        .position = vertex,
        .restitution = 1.0,
        .friction = 0.1,
    };

    try contacts.append(contact);
}

fn SAT_axis(i: u32, a: *Body, b: *Body) zm.Vec {
    var axis: zm.Vec = .{0.0,0.0,0.0,0.0};
    switch (i) {
        0 => {
            axis = a.getXAxis();
        },
        1 => {
            axis = zm.mul(zm.Vec{0.0, 1.0, 0.0, 0.0}, zm.matFromQuat(a.*.orientation));
        },
        2 => {
            axis = zm.mul(zm.Vec{0.0, 0.0, 1.0, 0.0}, zm.matFromQuat(a.*.orientation));
        },
        3 => {
            axis = zm.mul(zm.Vec{1.0, 0.0, 0.0, 0.0}, zm.matFromQuat(b.*.orientation));
        },
        4 => {
            axis = zm.mul(zm.Vec{0.0, 1.0, 0.0, 0.0}, zm.matFromQuat(b.*.orientation));
        },
        5 => {
            axis = zm.mul(zm.Vec{0.0, 0.0, 1.0, 0.0}, zm.matFromQuat(b.*.orientation));
        },
        6 => {
            axis = zm.cross3(
                zm.mul(zm.Vec{1.0, 0.0, 0.0, 0.0}, zm.matFromQuat(a.*.orientation)),
                zm.mul(zm.Vec{1.0, 0.0, 0.0, 0.0}, zm.matFromQuat(b.*.orientation))
                );
        },
        7 => {
            axis = zm.cross3(
                zm.mul(zm.Vec{1.0, 0.0, 0.0, 0.0}, zm.matFromQuat(a.*.orientation)),
                zm.mul(zm.Vec{0.0, 1.0, 0.0, 0.0}, zm.matFromQuat(b.*.orientation))
                );
        },
        8 => {
            axis = zm.cross3(
                zm.mul(zm.Vec{1.0, 0.0, 0.0, 0.0}, zm.matFromQuat(a.*.orientation)),
                zm.mul(zm.Vec{0.0, 0.0, 1.0, 0.0}, zm.matFromQuat(b.*.orientation))
                );
        },
        9 => {
            axis = zm.cross3(
                zm.mul(zm.Vec{0.0, 1.0, 0.0, 0.0}, zm.matFromQuat(a.*.orientation)),
                zm.mul(zm.Vec{1.0, 0.0, 0.0, 0.0}, zm.matFromQuat(b.*.orientation))
                );
        },
        10 => {
            axis = zm.cross3(
                zm.mul(zm.Vec{0.0, 1.0, 0.0, 0.0}, zm.matFromQuat(a.*.orientation)),
                zm.mul(zm.Vec{0.0, 1.0, 0.0, 0.0}, zm.matFromQuat(b.*.orientation))
                );
        },
        11 => {
            axis = zm.cross3(
                zm.mul(zm.Vec{0.0, 1.0, 0.0, 0.0}, zm.matFromQuat(a.*.orientation)),
                zm.mul(zm.Vec{0.0, 0.0, 1.0, 0.0}, zm.matFromQuat(b.*.orientation))
                );
        },
        12 => {
            axis = zm.cross3(
                zm.mul(zm.Vec{0.0, 0.0, 1.0, 0.0}, zm.matFromQuat(a.*.orientation)),
                zm.mul(zm.Vec{1.0, 0.0, 0.0, 0.0}, zm.matFromQuat(b.*.orientation))
                );
        },
        13 => {
            axis = zm.cross3(
                zm.mul(zm.Vec{0.0, 0.0, 1.0, 0.0}, zm.matFromQuat(a.*.orientation)),
                zm.mul(zm.Vec{0.0, 1.0, 0.0, 0.0}, zm.matFromQuat(b.*.orientation))
                );
        },
        14 => {
            axis = zm.cross3(
                zm.mul(zm.Vec{0.0, 0.0, 1.0, 0.0}, zm.matFromQuat(a.*.orientation)),
                zm.mul(zm.Vec{0.0, 0.0, 1.0, 0.0}, zm.matFromQuat(b.*.orientation))
                );
        },
        else => {},
    }
    return axis;
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

    const a_projected_length: f32 = zm.length3(a_projected)[0];
    const b_projected_length: f32 = zm.length3(b_projected)[0];

    const distance: f32 = zm.length3(cm.projectV(axis, ab_center_line))[0];
    
    return a_projected_length + b_projected_length - distance;
}
