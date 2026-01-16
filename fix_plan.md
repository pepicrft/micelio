# Micelio Fix Plan

## Completed Tasks

### ✅ HIGH PRIORITY: Replace gRPC C++ with nghttp2 (COMPLETE)

**Problem:** The gRPC implementation used 1.1GB of vendor code and took 10+ minutes to build.

**Solution Implemented:**
- Created `hif/src/grpc/http2_client.c` - lightweight gRPC client using nghttp2 + OpenSSL
- Updated `hif/build.zig` to use nghttp2 backend by default
- Removed `hif/vendor/grpc` directory (saved 1.1GB)
- Removed `hif/scripts/fetch_grpc_deps.sh`

**Results:**
| Metric | Before | After |
|--------|--------|-------|
| Build time | 10+ minutes | **15 seconds** |
| Vendor size | 1.1GB | 0 (uses system libs) |
| Dependencies | grpc C++, cmake | nghttp2, openssl |

**Files Changed:**
- `hif/src/grpc/http2_client.c` - NEW: Lightweight gRPC implementation
- `hif/build.zig` - Updated to support nghttp2 backend (default)
- `hif/src/diff.zig` - Fixed Zig 0.15 ArrayList API
- `hif/src/session.zig` - Added stub for resolve function

**Files Removed:**
- `hif/vendor/grpc/` - Entire 1.1GB directory
- `hif/scripts/fetch_grpc_deps.sh` - No longer needed

**Verification:**
- ✅ Clean build in 15 seconds
- ✅ All unit tests pass
- ✅ Executable runs and shows help
- ✅ Links correctly to nghttp2, ssl, crypto

---

## Architecture Notes

### gRPC Wire Protocol
The new implementation (`http2_client.c`) implements the gRPC wire protocol:
- HTTP/2 with headers: `:method POST`, `:path /service/Method`, `content-type: application/grpc`
- Message framing: 5-byte header (1 byte compression + 4 bytes BE length) + protobuf
- Trailer headers: `grpc-status`, `grpc-message`

### Dependencies
System packages required:
```bash
apt-get install libnghttp2-dev libssl-dev
```

### Build Commands
```bash
# Default build (nghttp2 backend)
zig build

# Run tests
zig build test

# Clean build
rm -rf zig-out .zig-cache && zig build
```

---

## Pending Tasks

### Test against production forge
- [ ] Test authentication flow with real credentials
- [ ] Test content API (GetHeadTree, GetBlob, GetPath)
- [ ] Test sessions API (StartSession, LandSession, ListSessions)

### Consider streaming RPCs
The current implementation only supports unary calls. If bidirectional streaming is needed, the http2_client.c would need to be extended.
