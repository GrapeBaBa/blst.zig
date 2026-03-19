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
        if (std.Target.x86.featureSetHas(target.result.cpu.features, .adx)) {
            lib.root_module.addCMacro("__ADX__", "");
        }
    }

    if (target.result.cpu.arch == .aarch64) lib.root_module.addCMacro("__ARM_FEATURE_CRYPTO", "1");

    if (target.result.cpu.arch != .x86_64 and
        target.result.cpu.arch != .aarch64)
    {
        lib.root_module.addCMacro("__BLST_NO_ASM__", "");
    }

    // Zig's bundled clang does not automatically define __APPLE__ when compiling
    // .S assembly files, even on a macOS target. blst's build/assembly.S uses
    // #ifdef __APPLE__ to select the mach-o ARM64 symbol variants; without this
    // flag the ELF branch is used instead and the mach-o symbols are missing,
    // causing undefined-symbol linker errors on Apple Silicon.
    // Note: must be in c_flags (passed to clang), not addCMacro (zig-only flags).
    if (target.result.os.tag == .macos) {
        try c_flags.append(b.allocator, "-D__APPLE__=1");
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
