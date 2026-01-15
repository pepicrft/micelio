//! hif library entry points.
//!
//! This is the main entry point for the hif library, providing access to:
//! - Core algorithms (hash, hlc, bloom, tree) via their respective namespaces
//!
//! Note: hif uses a forge-first architecture where repositories exist on the
//! server (forge), not locally. There is no local repository initialization.
//! Use `hif clone <repo>` to set up local state for working with a forge repo.

const std = @import("std");

// Core algorithms
pub const hash = @import("core/hash.zig");
pub const hlc = @import("core/hlc.zig");
pub const bloom = @import("core/bloom.zig");
pub const tree = @import("core/tree.zig");

// Re-export commonly used types for convenience
pub const Hash = hash.Hash;
pub const HLC = hlc.HLC;
pub const Clock = hlc.Clock;
pub const Bloom = bloom.Bloom;
pub const Tree = tree.Tree;
