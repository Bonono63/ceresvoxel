//! Physics runtime and algorithm
const std = @import("std");
const zm = @import("zmath");
const cm = @import("ceresmath.zig");
const chunk = @import("chunk.zig");
const main = @import("main.zig");

const GRAVITATIONAL_CONSTANT: f128 = 6.67428e-11;
pub const AU: f128 = 149.6e9;
pub const SCALE: f32 = 50.0;

pub const Body = struct {
    // This should be sufficient for space exploration at a solar system level
    position: @Vector(3, f128),
    // There is phyicsally no reason to be able to go above a speed or acceleration of 2.4 billion meters a second
    velocity: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, // meters per second
    // TODO decide whether a f32 is sufficient precision for mass calculations
    inverse_mass: f32,
    // Sum accelerations of the forces acting on the particle
    force_accumulation: zm.Vec = .{0.0, 0.0, 0.0, 0.0},
    // Helps with simulation stability, but for space it doesn't make much sense
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
    sun_index: u32 = 0,
    sim_start_time: i64,

    // Should only ever be used for writes from the logic thread
    new_bodies: [2]std.ArrayList(Body) = undefined,
    new_particle_handles: [2]std.ArrayList(*main.ParticleHandle) = undefined,
    new_index: u32 = 0,

    // Copies the current bodies to a double buffer and swaps between the two for the most recent data
    // Should only ever be used for reads
    display_bodies: [2][]Body = undefined,
    display_index: u32 = 0,
    copying: bool = false,
    //display_mutex: std.Thread.Mutex = std.Thread.Mutex{},

    mutex: std.Thread.Mutex = std.Thread.Mutex{},
    motion_style: PlanetaryMotionStyle = PlanetaryMotionStyle.DETERMINISTIC,
};

// TODO abstract the voxel spaces and entities to one type of physics entity
pub fn physics_tick(delta_time: f64, bodies: []Body, physics_state: *PhysicsState) void {
    // Planetary Motion
    for (0..bodies.len) |index| {
        if (bodies[index].planet) {
            switch (physics_state.motion_style) {

                PlanetaryMotionStyle.DETERMINISTIC => {
                    //const prev_position = bodies[index].position;
                    const time = @as(f64, @floatFromInt(std.time.milliTimestamp() - physics_state.sim_start_time));
                    const x: f128 = bodies[index].orbit_radius * @cos(time / bodies[index].orbit_radius / bodies[index].orbit_radius);
                    const z: f128 = bodies[index].orbit_radius * @sin(time / bodies[index].orbit_radius / bodies[index].orbit_radius);
                    const y: f128 = bodies[index].eccliptic_offset[0] * x + bodies[index].eccliptic_offset[1] * z;

                    bodies[index].position = .{x,y,z};
                },

                PlanetaryMotionStyle.NONDETERMINISTIC => {
                    const sun_position: @Vector(3, f128) = .{0.0,0.0,0.0};
                    // F = G * m1 * m2 / d**2
                    const d = 1.0 / cm.distance_f128(bodies[index].position, sun_position);
                    const force_coefficient: f128 = GRAVITATIONAL_CONSTANT * (1.0/bodies[index].inverse_mass) * (1.0/bodies[physics_state.*.sun_index].inverse_mass) * d * d;
                    
                    const difference: @Vector(3, f32) = .{
                        @as(f32, @floatCast(sun_position[0]-bodies[index].position[0])),
                        @as(f32, @floatCast(sun_position[1]-bodies[index].position[1])),
                        @as(f32, @floatCast(sun_position[2]-bodies[index].position[2])),
                    };
                    const theta: f32 = std.math.atan2(difference[2], difference[0]);
                    const fx = @cos(theta) * @as(f32, @floatCast(force_coefficient));
                    const fy = @sin(theta) * @as(f32, @floatCast(force_coefficient));

                    const final: zm.Vec = .{
                        fx,
                        0.0,
                        fy,
                        0.0,
                    };

                    //std.debug.print("d: {} gc: {} fv: {} f64 {}\n ", .{d, force_coefficient, final_vector, final_f64});
                    bodies[index].force_accumulation += final;
                },
            }
        }
    }

    // Gravity
    for (0..bodies.len) |index| {
        _ = &index;
    }

    // Bouyancy
    // Magnetism

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

//fn generate_contacts(allocator: *const std.Allocator, a: *Body, a_offset: zm.Mat, b: *Body, b_offset: zm.Mat) ![]Contact {
//    return ;
//}

