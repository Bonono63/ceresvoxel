//! Physics runtime and algorithm
const std = @import("std");
const zm = @import("zmath");
const chunk = @import("chunk.zig");

const GRAVITATIONAL_CONSTANT: f32 = 0.000000000066743015;

pub const Particle = struct {
    // This should be sufficient for space exploration at a solar system level
    postition: @Vector(3, f128),
    // There is phyicsally no reason to be able to go above a speed or acceleration of 2.4 billion meters a second
    velocity: zm.Vec,
    // TODO decide whether a f32 is sufficient precision for mass calculations
    inverse_mass: f32,
    // Sum accelerations of the forces acting on the particle
    force_accumulation: zm.Vec,
    // Helps with simulation stability, but for space it doesn't make much sense
    damp: f32 = 0.00001,
};

pub const PhysicsState = struct {
    particles: std.ArrayList();
};

pub fn physics_thread() void {

}

// TODO abstract the voxel spaces and entities to one type of physics entity
fn physics_tick(delta_time: f64, particles: []Particle) void {
    // Gravity
    for (particles) |particle| {
        var sum_gravity_force: zm.Vec = .{0.0,0.0,0.0,0.0};
        for (particles) |other_particle| {
            if (other_particle != particle) {
                const distance = distance_128(particle.position, other_particle.position);
                sum_gravity_force += GRAVITATIONAL_CONSTANT / (distance * distance * particle.inverse_mass * other_particle.inverse_mass);
            }
        }
        particle.force_accumulation += sum_gravity_force;
    }

    // Bouyancy
    // Magnetism

    // Integrator (basically actually do the physics)
    for (particles) |particle| {
        if (particle.inverse_mass > 0.0) {
            // velocity integration
            particle.position += particle.velocity * delta_time;
            // acceleration integration
            const accumulated_acceleration = particle.force_accumulation * particle.inverse_mass;
            particle.velocity += accumulated_acceleration * delta_time;

            particle.velocity *= particle.damp;

            particle.force_accumulation = .{0.0,0.0,0.0};
        }
    }
}

pub fn distance_128(a: @Vector(3, f128), b: @Vector(3, f128)) f128 {
    const x = a[0] - b[0];
    const y = a[1] - b[1];
    const z = a[2] - b[2];
    return std.math.sqrt(x * x + y * y + z * z);
}
