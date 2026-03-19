const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const portable = b.option(bool, "portable", "turn on portable mode") orelse false;

    const upstream = b.dependency("blst", .{});

    var c_flags = std.ArrayList([]const u8).empty;
    defer c_flags.deinit(b.allocator);

    try c_flags.append(b.allocator, "-fno-builtin");
    try c_flags.append(b.allocator, "-Wno-unused-function");
    try c_flags.append(b.allocator, "-Wno-unused-command-line-argument");

    if (target.result.cpu.arch == .x86_64) {
        try c_flags.append(b.allocator, "-mno-avx"); // avoid costly transitions
    }

    const lib = b.addLibrary(.{
        .name = "blst",
        .root_module = b.createModule(
            .{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            },
        ),
    });

    if (portable) {
        lib.root_module.addCMacro("__BLST_PORTABLE__", "");
    } else {
        // Guard __ADX__ check to x86_64 only.
        // std.Target.x86.featureSetHas on non-x86 cpu features is meaningless —
        // the feature indices differ per-arch and may accidentally return true
        // for unrelated ARM features, incorrectly defining __ADX__ and breaking
        // symbol resolution (server.c then references ctx_* symbols that don't
        // exist in the mach-o/elf ARM64 assembly).
        if (target.result.cpu.arch == .x86_64 and
            std.Target.x86.featureSetHas(target.result.cpu.features, .adx))
        {
            lib.root_module.addCMacro("__ADX__", "");
        }
    }

    if (target.result.cpu.arch == .aarch64) lib.root_module.addCMacro("__ARM_FEATURE_CRYPTO", "1");

    if (target.result.cpu.arch != .x86_64 and
        target.result.cpu.arch != .aarch64)
    {
        lib.root_module.addCMacro("__BLST_NO_ASM__", "");
    }

    lib.installHeader(upstream.path("bindings/blst.h"), "blst.h");
    lib.installHeader(upstream.path("bindings/blst_aux.h"), "blst_aux.h");

    lib.root_module.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "src/server.c",
            "build/assembly.S",
        },
        .flags = c_flags.items,
    });

    b.installArtifact(lib);
}
