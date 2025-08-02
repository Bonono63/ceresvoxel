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
    acceleration: zm.Vec = .{0.0, 0.0, 0.0, 0.0},
    // TODO decide whether a f32 is sufficient precision for mass calculations
    inverse_mass: f64,
    // Sum accelerations of the forces acting on the particle
    force_accumulation: @Vector(3, f64) = .{0.0, 0.0, 0.0},
    // Helps with simulation stability, but for space it doesn't make much sense
    damp: f32 = 0.99999,

    planet: bool = false,
    orbit_center_position: @Vector(3, f128) = .{0.0,0.0,0.0},
    eccentricity: f32 = 1.0,
    orbit_radius: f128 = 10.0,
    period: f32 = 1000.0,
    // the plane the ellipse is mapped to
    plane: @Vector(2, f32) = .{1.0,1.0}
};

// TODO maybe planets belong in a different array or structure, but for now they are the same
pub const PhysicsState = struct {
    particles: std.ArrayList(Particle),
    // TODO make sure this is initialized properly when loading from disk 
    physics_tick_count: u32 = 0,
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
            
            physics_tick(delta_time_float, physics_state.physics_tick_count, physics_state.particles.items);
            
            last_interval = current_time;
            std.debug.print("{:2} {d:3}ms\r", .{counter, delta_time_float});
            if (counter >= counter_max) {
                counter = 0;
            } else {
                counter += 1;
            }
            physics_state.physics_tick_count += 1;
        }
    }

    done.* = true;
}

// TODO abstract the voxel spaces and entities to one type of physics entity
fn physics_tick(delta_time: f64, physics_tick_count: u32, particles: []Particle) void {
    // Planetary Motion
    for (0..particles.len) |index| {
        if (particles[index].planet) {
            const x: f128 = particles[index].orbit_radius * @cos(@as(f32, @floatFromInt(physics_tick_count)) / particles[index].period) + particles[index].orbit_center_position[0]; // parameterization of x in an ellipse
            const z: f128 = particles[index].orbit_radius * @sin(@as(f32, @floatFromInt(physics_tick_count)) / particles[index].period) + particles[index].orbit_center_position[2]; // plug in a plane
            const y: f128 = particles[index].plane[0] * x + particles[index].plane[1] * z + particles[index].orbit_center_position[1]; // parameterization of y in an ellipse
            particles[index].position = .{x,y,z};
        }
    }

    // Gravity
    for (0..particles.len) |index| {
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
        if (!particles[index].planet) {
            particles[index].force_accumulation += .{0.0, -1.0 / particles[index].inverse_mass, 0.0};
        }
    }

    // Bouyancy
    // Magnetism

    // Classical Mechanics (Integrator) 
    for (0..particles.len) |index| {
        if (particles[index].inverse_mass > 0.0 and !particles[index].planet) {
            // velocity integration
            particles[index].position += .{
                particles[index].velocity[0] * delta_time,
                particles[index].velocity[1] * delta_time,
                particles[index].velocity[2] * delta_time,
            };
            //var resulting_acceleration = scale_f64(particles[index].acceleration, @floatCast(delta_time));
            // acceleration integration
            var resulting_acceleration = scale_f64(particles[index].force_accumulation, particles[index].inverse_mass);
            resulting_acceleration = scale_f64(resulting_acceleration, @floatCast(delta_time));
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

pub fn scale_f32(vec: @Vector(4, f32), scale: f32) @Vector(4, f32){
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale, vec[3] * scale};
}

pub fn scale_f64(vec: @Vector(3, f64), scale: f64) @Vector(3, f64){
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale};
}

pub fn scale_f128(vec: @Vector(3, f128), scale: f32) @Vector(3, f128){
    return .{vec[0] * scale, vec[1] * scale, vec[2] * scale};
}
