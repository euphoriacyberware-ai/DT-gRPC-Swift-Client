#!/usr/bin/env bash
#
# Regenerates the protobuf, gRPC and FlatBuffers sources in
# Sources/DrawThingsClient/Generated from the schemas in Protos/.
#
# The protoc plugins are built from this package's resolved dependencies, so the
# generated code always matches the swift-protobuf / grpc-swift-protobuf runtime
# pinned in Package.resolved. Requires `protoc` and `flatc` (25.9.23) on PATH.
#
# Usage:
#   Scripts/generate.sh                 # regenerate from Protos/
#   Scripts/generate.sh --sync <path>   # first copy schemas from a draw-things-community checkout
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTOS="$ROOT/Protos"
OUT="$ROOT/Sources/DrawThingsClient/Generated"
FLATC_VERSION="25.9.23"

if [[ "${1:-}" == "--sync" ]]; then
  COMMUNITY="${2:?usage: generate.sh --sync <path-to-draw-things-community>}"
  cp "$COMMUNITY/Libraries/GRPC/Models/Sources/imageService/imageService.proto" "$PROTOS/"
  cp "$COMMUNITY/Libraries/DataModels/Sources/config.fbs" "$PROTOS/"
  echo "Synced schemas from $COMMUNITY ($(git -C "$COMMUNITY" rev-parse --short HEAD 2>/dev/null || echo unknown))"
fi

command -v protoc >/dev/null || { echo "error: protoc not found" >&2; exit 1; }
command -v flatc >/dev/null || { echo "error: flatc not found" >&2; exit 1; }
if ! flatc --version | grep -q "$FLATC_VERSION"; then
  echo "error: flatc $FLATC_VERSION required (matches the FlatBuffers package pin), found: $(flatc --version)" >&2
  exit 1
fi

echo "Building protoc plugins from resolved dependencies..."
swift build --package-path "$ROOT" -c release --product protoc-gen-swift >/dev/null
swift build --package-path "$ROOT" -c release --product protoc-gen-grpc-swift-2 >/dev/null
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"

mkdir -p "$OUT"
rm -f "$OUT"/imageService.pb.swift "$OUT"/imageService.grpc.swift "$OUT"/config_generated.swift

echo "Generating protobuf messages and gRPC client..."
protoc \
  --proto_path="$PROTOS" \
  --plugin=protoc-gen-swift="$BIN/protoc-gen-swift" \
  --plugin=protoc-gen-grpc-swift-2="$BIN/protoc-gen-grpc-swift-2" \
  --swift_opt=Visibility=Public \
  --swift_out="$OUT" \
  --grpc-swift-2_opt=Visibility=Internal,Server=false,Client=true \
  --grpc-swift-2_out="$OUT" \
  "$PROTOS/imageService.proto"

echo "Generating FlatBuffers configuration..."
# config.fbs is a Dflat schema: it uses the `primary` and `indexed` attributes,
# which Dflat declares itself. Declare them for plain flatc on a temporary copy.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
{ printf 'attribute "primary";\nattribute "indexed";\n'; cat "$PROTOS/config.fbs"; } > "$TMP/config.fbs"
flatc --swift --gen-object-api -o "$OUT" "$TMP/config.fbs"
# flatc does not emit Sendable, and Swift 6 only accepts a checked Sendable conformance
# in the declaring file, so add it to the (plain Int8) enums here.
sed -i '' -E 's/^(public enum [A-Za-z]+: Int8, Enum, Verifiable) \{/\1, Sendable {/' "$OUT/config_generated.swift"

echo "Done. Generated files:"
ls -1 "$OUT"
