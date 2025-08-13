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
    angular_velocity: zm.Vec = .{0.0,0.0,0.0,0.0}, // axis-angle representation
    angular_damping: f32 = 0.99999,
    transform: zm.Mat = zm.identity(), // Current body transform, can be used for rendering as well
    inverse_inertia_tensor_world: cm.Mat3 = cm.identity(),
    inverse_inertia_tensor: cm.Mat3 = cm.identity(),
    torque_accumulation: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, // the first 3 values are position, the 4th value is the strength of the torque
};

const PlanetaryMotionStyle = enum {
    DETERMINISTIC,
    NONDETERMINISTIC,
};

// TODO maybe planets belong in a different array or structure, but for now they are the same
pub const PhysicsState = struct {
    particles: std.ArrayList(Body),
    sun_index: u32 = 0,
    sim_start_time: i64,

    motion_style: PlanetaryMotionStyle = PlanetaryMotionStyle.DETERMINISTIC,
};

pub fn physics_thread(physics_state: *PhysicsState, game_state: *main.GameState, complete_signal: *bool, done: *bool) void {
    _ = &game_state;

    var last_interval: i64 = std.time.milliTimestamp();
    var counter: u8 = 1;
    const counter_max: u8 = 40;
    // 40 ticks a second = 25 ms
    const minimum_delta_time: u8 = 5;
    while (complete_signal.*) {
        const current_time = std.time.milliTimestamp();
        const delta_time = current_time - last_interval;
        if (delta_time > minimum_delta_time) {
            const delta_time_float: f64 = @as(f64, @floatFromInt(delta_time)) / 1000.0;

            // TODO replace this with linear impulses later
            physics_state.particles.items[game_state.player_state.physics_index].velocity = game_state.player_state.input_vec;
            
            physics_tick(delta_time_float, physics_state.particles.items, physics_state);
            
            last_interval = current_time;
            //std.debug.print("{any}\n", .{physics_state.particles.items[1]});
            std.debug.print("{d:3}ms {} particles\r", .{delta_time, physics_state.particles.items.len});
            if (counter >= counter_max) {
                counter = 0;
            } else {
                counter += 1;
            }
        }
    }

    done.* = true;
}

// TODO abstract the voxel spaces and entities to one type of physics entity
fn physics_tick(delta_time: f64, particles: []Body, physics_state: *PhysicsState) void {
    // Planetary Motion
    for (0..particles.len) |index| {
        if (particles[index].planet) {
            switch (physics_state.motion_style) {

                PlanetaryMotionStyle.DETERMINISTIC => {
                    //const prev_position = particles[index].position;
                    const time = @as(f64, @floatFromInt(std.time.milliTimestamp() - physics_state.sim_start_time));
                    const x: f128 = particles[index].orbit_radius * @cos(time / particles[index].orbit_radius / particles[index].orbit_radius);
                    const z: f128 = particles[index].orbit_radius * @sin(time / particles[index].orbit_radius / particles[index].orbit_radius);
                    const y: f128 = particles[index].eccliptic_offset[0] * x + particles[index].eccliptic_offset[1] * z;

                    particles[index].position = .{x,y,z};
                },

                PlanetaryMotionStyle.NONDETERMINISTIC => {
                    const sun_position: @Vector(3, f128) = .{0.0,0.0,0.0};
                    // F = G * m1 * m2 / d**2
                    const d = 1.0 / cm.distance_f128(particles[index].position, sun_position);
                    const force_coefficient: f128 = GRAVITATIONAL_CONSTANT * (1.0/particles[index].inverse_mass) * (1.0/particles[physics_state.*.sun_index].inverse_mass) * d * d;
                    
                    const difference: @Vector(3, f32) = .{
                        @as(f32, @floatCast(sun_position[0]-particles[index].position[0])),
                        @as(f32, @floatCast(sun_position[1]-particles[index].position[1])),
                        @as(f32, @floatCast(sun_position[2]-particles[index].position[2])),
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
                    particles[index].force_accumulation += final;
                },
            }
        }
    }

    // Gravity
    for (0..particles.len) |index| {
        _ = &index;
        //const particle = particles[index];
        //var sum_gravity_force: zm.Vec = .{0.0,0.0,0.0,0.0};
        //for (particles) |other_particle| {
        //    if (&other_particle != &particle) {
        //        const distance = distance_128(particle.position, other_particle.position);
        //        const gravity_strength = GRAVITATIONAL_CONSTANT / @as(f32, @floatCast((distance * distance * (1 / particle.inverse_mass * other_particle.inverse_mass))));
        //        const gravity_direction: zm.Vec = zm.normalize3(.{
        //            @as(f32, @floatCast(particle.position[0] - other_particle.position[0])),
        //            @as(f32, @floatCast(particle.position[1] - other_particle.position[1])),
        //            @as(f32, @floatCast(particle.position[2] - other_particle.position[2])),
        //            0.0,
        //        });
        //        sum_gravity_force += .{
        //            gravity_direction[0] * gravity_strength,
        //            gravity_direction[1] * gravity_strength,
        //            gravity_direction[2] * gravity_strength,
        //            0.0,
        //        };
        //    }
        //}
        //particles[index].force_accumulation += sum_gravity_force;
        
        //if (!particles[index].planet) {
        //    particles[index].force_accumulation += .{0.0, -1.0 / particles[index].inverse_mass, 0.0};
        //}
    }

    // Bouyancy
    // Magnetism

    // Classical Mechanics (Integrator) 
    for (0..particles.len) |index| {
        if (particles[index].inverse_mass > 0.0) {
            // linear acceleration integration
            const resulting_linear_acceleration = cm.scale_f32(particles[index].force_accumulation, particles[index].inverse_mass * @as(f32, @floatCast(delta_time)));
            particles[index].velocity += .{
                @as(f32, @floatCast(resulting_linear_acceleration[0])),
                @as(f32, @floatCast(resulting_linear_acceleration[1])),
                @as(f32, @floatCast(resulting_linear_acceleration[2])),
                0.0,
            };

            //const resulting_angular_acceleration = 

            // linear damping
            particles[index].velocity = cm.scale_f32(particles[index].velocity, particles[index].linear_damping);
            
            // angular damping
            particles[index].angular_velocity = cm.scale_f32(particles[index].angular_velocity, particles[index].angular_damping);

            // velocity integration
            particles[index].position += .{
                particles[index].velocity[0] * delta_time,
                particles[index].velocity[1] * delta_time,
                particles[index].velocity[2] * delta_time,
            };

            // reset forces
            particles[index].force_accumulation = .{0.0, 0.0, 0.0, 0.0};
            particles[index].torque_accumulation = .{0.0, 0.0, 0.0, 0.0};
        }
    }
}

