//! Physics runtime and algorithm
const std = @import("std");
const zm = @import("zmath");
const chunk = @import("chunk.zig");
const main = @import("main.zig");

const GRAVITATIONAL_CONSTANT: f128 = 6.67428e-11;
pub const AU: f128 = 149.6e9;
pub const SCALE: f32 = 10.0;

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
    orbit_center_position: @Vector(3, f128) = .{0.0,0.0,0.0},
    eccentricity: f32 = 1.0,

    /// Position divided by one AU
    pub fn pos_d_au(self: *Particle) @Vector(3, f32) {
        return .{
            @as(f32, @floatCast(self.position[0] / AU)),
            @as(f32, @floatCast(self.position[1] / AU)),
            @as(f32, @floatCast(self.position[2] / AU)),
        };
    }
};

// TODO maybe planets belong in a different array or structure, but for now they are the same
pub const PhysicsState = struct {
    particles: std.ArrayList(Particle),
    sun_index: u32 = 0,
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
            std.debug.print("{any}\n", .{physics_state.particles.items[1]});
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
            // F = G * m1 * m2 / d**2
            const d = distance_vector_128_squared(particles[index].position, .{0.0 ,0.0, 0.0});
            const inverse_d: @Vector(3, f128) = .{
                1.0 / d[0],
                1.0 / d[1],
                1.0 / d[2],
            };
            const gravity_coefficient = GRAVITATIONAL_CONSTANT * (1.0/particles[index].inverse_mass) * (1.0/particles[physics_state.*.sun_index].inverse_mass);
            const scaled_d: f64 = @as(f64, @floatCast((inverse_d[0] + inverse_d[1] + inverse_d[2]) * gravity_coefficient));
            
            const theta: f64 = std.math.atan2(@as(f64, @floatCast(inverse_d[0])), @as(f64, @floatCast(inverse_d[2])));
            const force_direction: @Vector(3, f64) = .{@cos(theta), 0.0, @sin(theta)};

            const final_vector: @Vector(3, f64) = scale_f64(force_direction, scaled_d);

            std.debug.print("{}\n ", .{d});

            //const final_vector: @Vector(3, f64) = .{
            //    @as(f64, @floatCast(scaled_d[0])),
            //    @as(f64, @floatCast(scaled_d[1])),
            //    @as(f64, @floatCast(scaled_d[2])),
            //};
            particles[index].force_accumulation += final_vector;
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

            //std.debug.print("v: {} a: {} ra: {}\n", .{particles[index].velocity, particles[index].acceleration, resulting_acceleration});

            particles[index].force_accumulation = .{0.0,0.0,0.0};
        }
    }
}

pub fn distance_128(a: @Vector(3, f128), b: @Vector(3, f128)) f128 {
    const x = a[0] - b[0];
    const y = a[1] - b[1];
    const z = a[2] - b[2];
    return std.math.sqrt(x * x + y * y + z * z);
}

pub fn distance_128_squared(a: @Vector(3, f128), b: @Vector(3, f128)) f128 {
    const x = a[0] - b[0];
    const y = a[1] - b[1];
    const z = a[2] - b[2];
    return x * x + y * y + z * z;
}

pub fn distance_vector_128_squared(a: @Vector(3, f128), b: @Vector(3, f128)) @Vector(3, f128) {
    const x = a[0] - b[0];
    const y = a[1] - b[1];
    const z = a[2] - b[2];
    return .{x * x, y * y, z * z};
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
