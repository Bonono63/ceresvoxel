//! Physics simulation runtime and data structures
//! This physics code is derived from the Cyclone Engine by Ian Millington
//! As well as Allen Chou's unity-physics-constraints tutorials.
//! As such this file is permissable under the MIT license
const std = @import("std");
const zphy = @import("zphysics");
const main = @import("main.zig");

pub const object_layers = struct {
    pub const non_moving: zphy.ObjectLayer = 0;
    pub const moving: zphy.ObjectLayer = 1;
    pub const len: u32 = 2;
};

pub const broad_phase_layers = struct {
    const non_moving: zphy.BroadPhaseLayer = 0;
    const moving: zphy.BroadPhaseLayer = 1;
    const len: u32 = 2;
};
pub const PhysicsSystemParameters = struct {
    broad_phase_layer_interface: *BroadPhaseLayerInterface,
    object_vs_broad_phase_layer_filter: *ObjectVsBroadPhaseLayerFilter,
    object_layer_pair_filter: *ObjectLayerPairFilter,
    contact_listener: *ContactListener,
};

const BroadPhaseLayerInterface = extern struct {
    broad_phase_layer_interface: zphy.BroadPhaseLayerInterface = .init(@This()),
    object_to_broad_phase: [object_layers.len]zphy.BroadPhaseLayer = undefined,

    fn init() BroadPhaseLayerInterface {
        var object_to_broad_phase: [object_layers.len]zphy.BroadPhaseLayer = undefined;
        object_to_broad_phase[object_layers.non_moving] = broad_phase_layers.non_moving;
        object_to_broad_phase[object_layers.moving] = broad_phase_layers.moving;
        return .{ .object_to_broad_phase = object_to_broad_phase };
    }

    fn selfPtr(broad_phase_layer_interface: *zphy.BroadPhaseLayerInterface) *BroadPhaseLayerInterface {
        return @alignCast(@fieldParentPtr("broad_phase_layer_interface", broad_phase_layer_interface));
    }

    fn selfPtrConst(broad_phase_layer_interface: *const zphy.BroadPhaseLayerInterface) *const BroadPhaseLayerInterface {
        return @alignCast(@fieldParentPtr("broad_phase_layer_interface", broad_phase_layer_interface));
    }

    pub fn getNumBroadPhaseLayers(_: *const zphy.BroadPhaseLayerInterface) callconv(.c) u32 {
        return broad_phase_layers.len;
    }

    pub fn getBroadPhaseLayer(
        broad_phase_layer_interface: *const zphy.BroadPhaseLayerInterface,
        layer: zphy.ObjectLayer,
    ) callconv(.c) zphy.BroadPhaseLayer {
        return selfPtrConst(broad_phase_layer_interface).object_to_broad_phase[layer];
    }
};

const ObjectVsBroadPhaseLayerFilter = extern struct {
    object_vs_broad_phase_layer_filter: zphy.ObjectVsBroadPhaseLayerFilter = .init(@This()),

    pub fn shouldCollide(
        _: *const zphy.ObjectVsBroadPhaseLayerFilter,
        layer1: zphy.ObjectLayer,
        layer2: zphy.BroadPhaseLayer,
    ) callconv(.c) bool {
        return switch (layer1) {
            object_layers.non_moving => layer2 == broad_phase_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const ObjectLayerPairFilter = extern struct {
    object_layer_pair_filter: zphy.ObjectLayerPairFilter = .init(@This()),

    pub fn shouldCollide(
        _: *const zphy.ObjectLayerPairFilter,
        object1: zphy.ObjectLayer,
        object2: zphy.ObjectLayer,
    ) callconv(.c) bool {
        return switch (object1) {
            object_layers.non_moving => object2 == object_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const ContactListener = extern struct {
    contact_listener: zphy.ContactListener = .init(@This()),

    fn selfPtr(contact_listener: *zphy.ContactListener) *ContactListener {
        return @alignCast(@fieldParentPtr("contact_listener", contact_listener));
    }

    fn selfPtrConst(contact_listener: *const zphy.ContactListener) *const ContactListener {
        return @alignCast(@fieldParentPtr("contact_listener", contact_listener));
    }

    pub fn onContactValidate(
        contact_listener: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        base_offset: *const [3]zphy.Real,
        collision_result: *const zphy.CollideShapeResult,
    ) callconv(.c) zphy.ValidateResult {
        _ = contact_listener;
        _ = body1;
        _ = body2;
        _ = base_offset;
        _ = collision_result;
        return .accept_all_contacts;
    }

    pub fn onContactAdded(
        contact_listener: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        _: *const zphy.ContactManifold,
        _: *zphy.ContactSettings,
    ) callconv(.c) void {
        _ = contact_listener;
        _ = body1;
        _ = body2;
    }

    pub fn onContactPersisted(
        contact_listener: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        _: *const zphy.ContactManifold,
        _: *zphy.ContactSettings,
    ) callconv(.c) void {
        _ = contact_listener;
        _ = body1;
        _ = body2;
    }

    pub fn onContactRemoved(
        contact_listener: *zphy.ContactListener,
        sub_shape_id_pair: *const zphy.SubShapeIdPair,
    ) callconv(.c) void {
        _ = contact_listener;
        _ = sub_shape_id_pair;
    }
};

pub fn physics_init(
    allocator: std.mem.Allocator,
    physics_system: **zphy.PhysicsSystem,
    params: *PhysicsSystemParameters,
) !void {
    try zphy.init(allocator, .{});

    params.broad_phase_layer_interface = try allocator.create(BroadPhaseLayerInterface);
    params.broad_phase_layer_interface.* = BroadPhaseLayerInterface.init();

    params.object_vs_broad_phase_layer_filter = try allocator.create(ObjectVsBroadPhaseLayerFilter);
    params.object_vs_broad_phase_layer_filter.* = .{};

    params.object_layer_pair_filter = try allocator.create(ObjectLayerPairFilter);
    params.object_layer_pair_filter.* = .{};

    params.contact_listener = try allocator.create(ContactListener);
    params.contact_listener.* = .{};

    // Create physics system
    physics_system.* = try zphy.PhysicsSystem.create(
        @as(*const zphy.BroadPhaseLayerInterface, @ptrCast(params.broad_phase_layer_interface)),
        @as(*const zphy.ObjectVsBroadPhaseLayerFilter, @ptrCast(params.object_vs_broad_phase_layer_filter)),
        @as(*const zphy.ObjectLayerPairFilter, @ptrCast(params.object_layer_pair_filter)),
        .{
            .max_bodies = 1024, // TODO increase substantially for later in development
            .num_body_mutexes = 0,
            .max_body_pairs = 1024,
            .max_contact_constraints = 1024,
        },
    );
}

pub fn physics_cleanup(
    allocator: std.mem.Allocator,
    physics_system: *zphy.PhysicsSystem,
    bodies: []main.Object,
    params: PhysicsSystemParameters,
) void {
    clear_bodies(physics_system, bodies);

    allocator.destroy(params.broad_phase_layer_interface);
    allocator.destroy(params.object_vs_broad_phase_layer_filter);
    allocator.destroy(params.object_layer_pair_filter);
    allocator.destroy(params.contact_listener);

    physics_system.destroy();
    zphy.deinit();
}

pub fn clear_bodies(
    physics_system: *zphy.PhysicsSystem,
    bodies: []main.Object,
) void {
    const body_interface = physics_system.*.getBodyInterfaceMut();

    for (bodies) |body| {
        body_interface.removeAndDestroyBody(body.physics_id);
        body.physics_shape.release();
        body.physics_settings.release();
    }
}
