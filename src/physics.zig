//! Physics runtime and algorithm
const std = @import("std");
const zm = @import("zmath");
const chunk = @import("chunk.zig");
const main = @import("main.zig");

const GRAVITATIONAL_CONSTANT: f32 = 0.000000000066743015;

pub const Particle = struct {
    // This should be sufficient for space exploration at a solar system level
    position: @Vector(3, f128),
    // There is phyicsally no reason to be able to go above a speed or acceleration of 2.4 billion meters a second
    velocity: zm.Vec = .{0.0, 0.0, 0.0, 0.0},
    // TODO decide whether a f32 is sufficient precision for mass calculations
    inverse_mass: f32,
    // Sum accelerations of the forces acting on the particle
    force_accumulation: zm.Vec = .{0.0, 0.0, 0.0, 0.0},
    // Helps with simulation stability, but for space it doesn't make much sense
    damp: f32 = 0.00001,
};

pub const PhysicsState = struct {
    particles: std.ArrayList(Particle)
};

pub fn physics_thread(physics_state: *PhysicsState, game_state: *main.GameState, complete_signal: *bool, done: *bool) void {
    _ = &game_state;

    var last_interval: i64 = std.time.milliTimestamp();
    var counter: u8 = 1;
    const counter_max: u8 = 40;
    const minimum_delta_time: u8 = 25;
    while (complete_signal.*) {
        const current_time = std.time.milliTimestamp();
        const delta_time = current_time - last_interval;
        // 40 ticks a second ?
        if (delta_time > minimum_delta_time) {
            const delta_time_float: f64 = @as(f64, @floatFromInt(delta_time)) / 1000.0;

            physics_state.particles.items[game_state.player_state.physics_index].velocity = game_state.player_state.input_vec;

            physics_tick(delta_time_float, physics_state.particles.items);
            last_interval = current_time;
            std.debug.print("{:2} {d:3}ms {}\r", .{counter, delta_time_float, game_state.player_state.input_vec});
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
fn physics_tick(delta_time: f64, particles: []Particle) void {
    // Gravity
    //for (0..particles.len) |index| {
    //    const particle = particles[index];
    //    var sum_gravity_force: zm.Vec = .{0.0,0.0,0.0,0.0};
    //    for (particles) |other_particle| {
    //        if (&other_particle != &particle) {
    //            const distance = distance_128(particle.position, other_particle.position);
    //            const gravity_strength = GRAVITATIONAL_CONSTANT / @as(f32, @floatCast((distance * distance * (1 / particle.inverse_mass * other_particle.inverse_mass))));
    //            const gravity_direction: zm.Vec = zm.normalize3(.{
    //                @as(f32, @floatCast(particle.position[0] - other_particle.position[0])),
    //                @as(f32, @floatCast(particle.position[1] - other_particle.position[1])),
    //                @as(f32, @floatCast(particle.position[2] - other_particle.position[2])),
    //                0.0,
    //            });
    //            sum_gravity_force += .{
    //                gravity_direction[0] * gravity_strength,
    //                gravity_direction[1] * gravity_strength,
    //                gravity_direction[2] * gravity_strength,
    //                0.0,
    //            };
    //        }
    //    }
    //    particles[index].force_accumulation += sum_gravity_force;
    //}

    // Bouyancy
    // Magnetism

    // Integrator (basically actually do the physics)
    for (0..particles.len) |index| {
        if (particles[index].inverse_mass > 0.0) {
            // velocity integration
            particles[index].position += .{
                particles[index].velocity[0] * delta_time,
                particles[index].velocity[1] * delta_time,
                particles[index].velocity[2] * delta_time,
            };
            // acceleration integration
            const accumulated_acceleration = scale_f32(particles[index].force_accumulation, particles[index].inverse_mass);
            particles[index].velocity += scale_f32(accumulated_acceleration, @floatCast(delta_time));

            particles[index].velocity = scale_f32(particles[index].velocity, particles[index].damp);

            particles[index].force_accumulation = .{0.0,0.0,0.0,0.0};
        }
    }
}

pub fn distance_128(a: @Vector(3, f128), b: @Vector(3, f128)) f128 {
    const x = a[0] - b[0];
    const y = a[1] - b[1];
    const z = a[2] - b[2];
    return std.math.sqrt(x * x + y * y + z * z);
}

pub fn scale_f32(vec: @Vector(4, f32), scale: f32) @Vector(4, f32){
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale, vec[3] * scale};
}

pub fn scale_128(vec: @Vector(3, f128), scale: f32) @Vector(3, f128){
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale};
}
