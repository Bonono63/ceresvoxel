const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const ceres_voxel = b.addExecutable(.{
        .name = "Engine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const vma_flags = [_][]const u8{
        "-c",
        "-fPIC",
    };

    ceres_voxel.root_module.addCSourceFile(.{ .file = .{ .cwd_relative = "vma_lib/vma.cpp" }, .flags = &vma_flags });
    ceres_voxel.addIncludePath(.{ .cwd_relative = "VulkanMemoryAllocator-3.2.1/include/" });
    ceres_voxel.addIncludePath(.{ .cwd_relative = "vma_lib/" });
    ceres_voxel.linkLibCpp();
    //ceres_voxel.addLibraryPath("");

    //ceres_voxel.addIncludePath(b.path("vma_lib"));

    // Hackery to get a cpp header only library to work with zig
    //ceres_voxel.addIncludePath(b.path("VulkanMemoryAllocator-3.2.1/include"));
    //ceres_voxel.addLibraryPath(b.path("vma_lib"));
    //ceres_voxel.linkSystemLibrary("vma");

    ceres_voxel.addIncludePath(b.path("glfw-3.4/include"));
    ceres_voxel.addLibraryPath(b.path("glfw-3.4/build/src"));

    if (target.result.os.tag == .windows) {
        ceres_voxel.linkSystemLibrary("glfw3");
    }
    // Make sure to build glfw as a dll because it doesn't like to
    // work otherwise
    if (target.result.os.tag == .linux) {
        ceres_voxel.linkSystemLibrary("glfw");
    }

    const zmath = b.dependency("zmath", .{});
    ceres_voxel.root_module.addImport("zmath", zmath.module("root"));

    const truetype = b.dependency("TrueType", .{});
    ceres_voxel.root_module.addImport("TrueType", truetype.module("TrueType"));

    // Should be built against the vulkan system library, building it yourself is
    // not really recomended
    if (target.result.os.tag == .linux)
        ceres_voxel.linkSystemLibrary("vulkan");
    if (target.result.os.tag == .windows) {
        // Absolute paths are nono for zig, but we can cheese it with
        // a directory link so here you go
        ceres_voxel.addIncludePath(b.path("vulkan_include"));
        ceres_voxel.addLibraryPath(b.path("vulkan_lib"));
        ceres_voxel.linkSystemLibrary("vulkan-1");
    }

    b.installArtifact(ceres_voxel);

    // This *creates* a Run step in the build graph, to be ceres_voxelcuted when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(ceres_voxel);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // TODO fix this
    //const exe_unit_tests = b.addTest(.{
    //    .root_source_file = b.path("src/main.zig"),
    //    .target = target,
    //    .optimize = optimize,
    //});

    //const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    //// Similar to creating the run step earlier, this exposes a `test` step to
    //// the `zig build --help` menu, providing a way for the user to request
    //// running the unit tests.
    //const test_step = b.step("test", "Run unit tests");
    //test_step.dependOn(&run_exe_unit_tests.step);
}
