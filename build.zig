const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "Engine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).

    exe.addIncludePath(b.path("vma_lib"));

    // Hackery to get a cpp header only library to work with zig
    exe.addIncludePath(b.path("VulkanMemoryAllocator-3.2.1/include"));
    exe.addLibraryPath(b.path("vma_lib"));
    exe.linkSystemLibrary("vma");

    exe.addIncludePath(b.path("glfw-3.4/include"));
    exe.addLibraryPath(b.path("glfw-3.4/build/src"));
    
    if (target.result.os.tag == .windows)
        exe.linkSystemLibrary("glfw3");
    // Make sure to build glfw as a dll because it doesn't like to
    // work otherwise
    if (target.result.os.tag == .linux)
        exe.linkSystemLibrary("glfw");
   
    const zmath = b.dependency("zmath", .{});
    exe.root_module.addImport("zmath", zmath.module("root"));
    
    // Should be built against the vulkan system library, building it yourself is
    // not really recomended
    if (target.result.os.tag == .linux)
        exe.linkSystemLibrary("vulkan");
    if (target.result.os.tag == .windows)
    {
        // Absolute paths are nono for zig, but we can cheese it with
        // a directory link so here you go
        exe.addIncludePath(b.path("vulkan_include"));
        exe.addLibraryPath(b.path("vulkan_lib"));
        exe.linkSystemLibrary("vulkan-1");
    }

    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

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
