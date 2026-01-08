const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const yazap_mod = b.addModule("yazap", .{
        .root_source_file = b.path("vendor/yazap/src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create the hif module
    const hif_mod = b.addModule("hif", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Executable (skip for WASM)
    var exe: ?*std.Build.Step.Compile = null;
    if (target.result.os.tag != .freestanding) {
        const exe_val = b.addExecutable(.{
            .name = "hif",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "hif", .module = hif_mod },
                    .{ .name = "yazap", .module = yazap_mod },
                },
            }),
        });
        b.installArtifact(exe_val);
        exe = exe_val;
    }

    // C ABI static library for FFI integration (skip for WASM)
    if (target.result.os.tag != .freestanding) {
        const ffi_lib = b.addLibrary(.{
            .name = "hif_ffi",
            .linkage = .static,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/ffi.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "hif", .module = hif_mod },
                },
            }),
        });
        ffi_lib.linkLibC();
        b.installArtifact(ffi_lib);

        // Install the C header file
        b.installFile("include/hif_core.h", "include/hif_core.h");
    }

    // Run step
    if (exe) |exe_val| {
        const run_cmd = b.addRunArtifact(exe_val);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    // Test step
    const test_step = b.step("test", "Run unit tests");

    // Core hash module tests
    const hash_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/core/hash.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(hash_tests).step);

    // Core HLC module tests
    const hlc_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/core/hlc.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(hlc_tests).step);

    // Core Bloom filter module tests
    const bloom_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/core/bloom.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(bloom_tests).step);

    // Core Tree module tests
    const tree_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/core/tree.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(tree_tests).step);

    // Unit tests for lib
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(lib_unit_tests).step);

    // Unit tests for exe
    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hif", .module = hif_mod },
                .{ .name = "yazap", .module = yazap_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(exe_unit_tests).step);

    // FFI module tests
    const ffi_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/ffi.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ffi_tests.linkLibC();
    test_step.dependOn(&b.addRunArtifact(ffi_tests).step);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hif", .module = hif_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(integration_tests).step);

    // Header sync tests (verify C header matches FFI exports)
    const header_sync_mod = b.createModule(.{
        .root_source_file = b.path("tests/header_sync.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Add include directory so @embedFile can find hif_core.h
    header_sync_mod.addAnonymousImport("hif_core.h", .{
        .root_source_file = b.path("include/hif_core.h"),
    });
    const header_sync_tests = b.addTest(.{
        .root_module = header_sync_mod,
    });
    test_step.dependOn(&b.addRunArtifact(header_sync_tests).step);
}
