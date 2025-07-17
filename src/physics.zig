//! Physics runtime and algorithm
const std = @import("std");
const zm = @import("zmath");
const chunk = @import("chunk.zig");

pub const Particle = struct {
    // This should be sufficient for space exploration at a solar system level
    postition: @Vector(3, f128),
    // There is phyicsally no reason to be able to go above a speed or acceleration of 2.4 billion meters a second
    velocity: @Vector(3, f32),
    // TODO decide whether a f32 is sufficient precision for mass calculations
    inverse_mass: f32,
    // Sum accelerations of the forces acting on the particle
    force_accumulation: @Vector(3, f32),
    // Basically helps with simulation stability
    //damp: f32 = 0.001,
};

// TODO abstract the voxel spaces and entities to one type of physics entity
pub fn physics_tick(delta_time: f64, particles: []Particle) void {
    // Integrator
    for (particles) |particle| {
        if (particle.inverse_mass > 0.0) {
            // velocity integration
            particle.position += particle.velocity * delta_time;
            // acceleration integration
            const accumulated_acceleration = particle.force_accumulation * particle.inverse_mass;
            particle.velocity += accumulated_acceleration * delta_time;

            //particle.velocity *= particle.damp;

            particle.force_accumulation = .{0.0,0.0,0.0};
        }
    }
}
