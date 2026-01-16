const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // gRPC option: "nghttp2" (default, lightweight) or "grpc" (legacy heavy)
    const grpc_backend = b.option([]const u8, "grpc-backend", "gRPC backend: nghttp2 (default) or grpc") orelse "nghttp2";
    const use_nghttp2 = std.mem.eql(u8, grpc_backend, "nghttp2");

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
        exe_val.addIncludePath(b.path("src"));
        exe_val.linkLibC();
        
        if (use_nghttp2) {
            // Lightweight nghttp2 backend (~200KB vs 1.1GB)
            exe_val.addCSourceFile(.{
                .file = b.path("src/grpc/http2_client.c"),
                .flags = &.{"-std=c11"},
            });
            exe_val.linkSystemLibrary("nghttp2");
            exe_val.linkSystemLibrary("ssl");
            exe_val.linkSystemLibrary("crypto");
        } else {
            // Legacy gRPC backend (heavy, 10+ minute build)
            exe_val.addCSourceFile(.{
                .file = b.path("src/grpc/client.c"),
                .flags = &.{"-std=c11"},
            });
            const grpc = addGrpc(b, optimize);
            exe_val.step.dependOn(grpc.step);
            exe_val.addIncludePath(grpc.include_dir);
            exe_val.addLibraryPath(grpc.lib_dir);
            exe_val.linkSystemLibrary("grpc");
            exe_val.linkSystemLibrary("gpr");
        }
        
        b.installArtifact(exe_val);
        exe = exe_val;
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

    // Core Serialize module tests
    const serialize_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/core/serialize.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(serialize_tests).step);

    // Config module tests
    const config_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/config.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(config_tests).step);

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

    // No FFI artifacts or header sync tests (CLI-first, no libhif-core).
}

const GrpcBuild = struct {
    step: *std.Build.Step,
    include_dir: std.Build.LazyPath,
    lib_dir: std.Build.LazyPath,
};

fn addGrpc(b: *std.Build, optimize: std.builtin.OptimizeMode) GrpcBuild {
    const grpc_source = b.path("vendor/grpc");
    const grpc_build = b.path("zig-out/grpc/build");
    const grpc_install = b.path("zig-out/grpc/install");

    const build_type = switch (optimize) {
        .Debug => "Debug",
        .ReleaseSafe => "RelWithDebInfo",
        .ReleaseFast => "Release",
        .ReleaseSmall => "MinSizeRel",
    };

    const configure = b.addSystemCommand(&.{
        "cmake",
        "-S",
        grpc_source.getPath(b),
        "-B",
        grpc_build.getPath(b),
        "-DCMAKE_CXX_STANDARD=17",
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
        "-DBUILD_SHARED_LIBS=ON",
        "-DgRPC_INSTALL=ON",
        "-DgRPC_BUILD_TESTS=OFF",
        "-DgRPC_BUILD_CODEGEN=OFF",
        "-DgRPC_BUILD_GRPC_CSHARP_EXT=OFF",
        "-DgRPC_BUILD_GRPC_CPP_PLUGIN=OFF",
        "-DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF",
        "-DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF",
        "-DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF",
        "-DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF",
        "-DgRPC_BUILD_GRPC_OBJECTIVE_C=OFF",
        "-DgRPC_BUILD_GRPCPP=OFF",
        "-DgRPC_SSL_PROVIDER=module",
        "-DgRPC_ABSL_PROVIDER=module",
        "-DgRPC_CARES_PROVIDER=module",
        "-DgRPC_RE2_PROVIDER=module",
        "-DgRPC_ZLIB_PROVIDER=module",
        "-DgRPC_PROTOBUF_PROVIDER=module",
        b.fmt("-DCMAKE_BUILD_TYPE={s}", .{build_type}),
        b.fmt("-DCMAKE_INSTALL_PREFIX={s}", .{grpc_install.getPath(b)}),
    });

    const fetch_deps = b.addSystemCommand(&.{
        "sh",
        b.path("scripts/fetch_grpc_deps.sh").getPath(b),
    });
    configure.step.dependOn(&fetch_deps.step);

    const cmake_build = b.addSystemCommand(&.{
        "cmake",
        "--build",
        grpc_build.getPath(b),
        "--target",
        "install",
    });
    cmake_build.step.dependOn(&configure.step);

    return .{
        .step = &cmake_build.step,
        .include_dir = b.path("zig-out/grpc/install/include"),
        .lib_dir = b.path("zig-out/grpc/install/lib"),
    };
}
