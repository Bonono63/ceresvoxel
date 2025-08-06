//! Physics runtime and algorithm
const std = @import("std");
const zm = @import("zmath");
const chunk = @import("chunk.zig");
const main = @import("main.zig");

const GRAVITATIONAL_CONSTANT: f128 = 6.67428e-11;
pub const AU: f128 = 149.6e9;
pub const SCALE: f32 = 50.0;

pub const Particle = struct {
    // This should be sufficient for space exploration at a solar system level
    position: @Vector(3, f128),
    // There is phyicsally no reason to be able to go above a speed or acceleration of 2.4 billion meters a second
    velocity: zm.Vec = .{0.0, 0.0, 0.0, 0.0}, // meters per second
    // TODO decide whether a f32 is sufficient precision for mass calculations
    inverse_mass: f64,
    // Sum accelerations of the forces acting on the particle
    force_accumulation: @Vector(3, f64) = .{0.0, 0.0, 0.0},
    // Helps with simulation stability, but for space it doesn't make much sense
    damp: f32 = 0.99999,

    gravity: bool = true,
    planet: bool = false,
    orbit_radius: f128 = 0.0,
    barocenter: @Vector(3, f128) = .{0.0,0.0,0.0}, // center of the object's orbit
    eccentricity: f32 = 1.0,
    eccliptic_offset: @Vector(2, f32) = .{0.0, 0.0},

    /// Position divided by one AU
    pub fn pos_d_au(self: *Particle) @Vector(3, f32) {
        return .{
            @as(f32, @floatCast(self.position[0] / AU)) * SCALE,
            @as(f32, @floatCast(self.position[1] / AU)) * SCALE,
            @as(f32, @floatCast(self.position[2] / AU)) * SCALE,
        };
    }
};

const PlanetaryMotionStyle = enum {
    DETERMINISTIC,
    NONDETERMINISTIC,
};

// TODO maybe planets belong in a different array or structure, but for now they are the same
pub const PhysicsState = struct {
    particles: std.ArrayList(Particle),
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
fn physics_tick(delta_time: f64, particles: []Particle, physics_state: *PhysicsState) void {
    // Planetary Motion
    for (0..particles.len) |index| {
        if (particles[index].planet) {
            switch (physics_state.motion_style) {
                PlanetaryMotionStyle.DETERMINISTIC => {
                    //const prev_position = particles[index].position;
                    const time = @as(f64, @floatFromInt(std.time.milliTimestamp() - physics_state.sim_start_time));
                    const x: f128 = particles[index].orbit_radius * @cos(time / particles[index].orbit_radius / particles[index].orbit_radius);
                    const y: f128 = 0.0;
                    const z: f128 = particles[index].orbit_radius * @sin(time / particles[index].orbit_radius / particles[index].orbit_radius);

                    particles[index].position = .{x,y,z};
                },
                PlanetaryMotionStyle.NONDETERMINISTIC => {
                    const sun_position: @Vector(3, f128) = .{0.0,0.0,0.0};
                    // F = G * m1 * m2 / d**2
                    const d = 1.0 / distance_f128(particles[index].position, sun_position);
                    const force_coefficient: f128 = GRAVITATIONAL_CONSTANT * (1.0/particles[index].inverse_mass) * (1.0/particles[physics_state.*.sun_index].inverse_mass) * d * d;
                    
                    const difference: @Vector(3, f64) = .{
                        @as(f64, @floatCast(sun_position[0]-particles[index].position[0])),
                        @as(f64, @floatCast(sun_position[1]-particles[index].position[1])),
                        @as(f64, @floatCast(sun_position[2]-particles[index].position[2])),
                    };
                    const theta: f64 = std.math.atan2(difference[2], difference[0]);
                    const fx = @cos(theta) * @as(f64, @floatCast(force_coefficient));
                    const fy = @sin(theta) * @as(f64, @floatCast(force_coefficient));

                    const final_f64: @Vector(3, f64) = .{
                        fx,
                        0.0,
                        fy,
                    };

                    //std.debug.print("d: {} gc: {} fv: {} f64 {}\n ", .{d, force_coefficient, final_vector, final_f64});
                    particles[index].force_accumulation += final_f64;
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
            // velocity integration
            particles[index].position += .{
                particles[index].velocity[0] * delta_time,
                particles[index].velocity[1] * delta_time,
                particles[index].velocity[2] * delta_time,
            };

            // acceleration integration
            const resulting_acceleration = scale_f64(particles[index].force_accumulation, particles[index].inverse_mass * delta_time);
            particles[index].velocity += .{
                @as(f32, @floatCast(resulting_acceleration[0])),
                @as(f32, @floatCast(resulting_acceleration[1])),
                @as(f32, @floatCast(resulting_acceleration[2])),
                0.0,
            };

            // damping
            particles[index].velocity = scale_f32(particles[index].velocity, particles[index].damp);

            //std.debug.print("p: {d:.3} {d:.3} {d:.3} v: {} fa: {}\n", .{
            //    particles[index].position[0],
            //    particles[index].position[1],
            //    particles[index].position[2],
            //    particles[index].velocity, resulting_acceleration});

            particles[index].force_accumulation = .{0.0,0.0,0.0};
        }
    }
}

pub fn distance_f128(a: @Vector(3, f128), b: @Vector(3, f128)) f128 {
    const x = a[0] - b[0];
    const y = a[1] - b[1];
    const z = a[2] - b[2];
    return std.math.sqrt(x * x) + std.math.sqrt(y * y) + std.math.sqrt(z * z);
}

pub fn scale_f32(vec: @Vector(4, f32), scale: f32) @Vector(4, f32){
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale, vec[3] * scale};
}

pub fn scale_f64(vec: @Vector(3, f64), scale: f64) @Vector(3, f64){
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale};
}

pub fn scale_f128(vec: @Vector(3, f128), scale: f128) @Vector(3, f128){
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale};
}

pub fn normalize_f128(a: @Vector(3, f128)) @Vector(3, f128) {
    const d = distance_f128(a, .{0.0,0.0,0.0});
    return .{a[0]/d, a[1]/d, a[2]/d};
}
