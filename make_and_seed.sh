#!/usr/bin/env bash
set -Eeuo pipefail

# Trackerless torrent creator + aria2 seeder
#
# Usage:
#   ./make_and_seed.sh "/path/to/file-or-directory"

DHT_PORT=5002
BT_PORT=5001
SEED_TIME=10080       # minutes = 7 days
SEED_RATIO=0.0        # no upload-ratio limit

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Error: required command not found: $1" >&2
        exit 1
    }
}

usage() {
    cat <<'EOF'
Usage:
  make_and_seed.sh "/path/to/file-or-directory"

Examples:
  ./make_and_seed.sh "/home/user/Downloads/file.iso"
  ./make_and_seed.sh "/home/user/Downloads/MyFolder"
EOF
}

if [[ $# -ne 1 ]]; then
    usage >&2
    exit 2
fi

require_command mktorrent
require_command aria2c
require_command realpath

source_path="$(realpath -e -- "$1")"

# Accept one existing ordinary file OR directory.
if [[ ! -f "$source_path" && ! -d "$source_path" ]]; then
    echo "Error: source must be an existing file or directory:" >&2
    echo "  $source_path" >&2
    exit 1
fi

source_parent="$(dirname -- "$source_path")"
source_name="$(basename -- "$source_path")"
torrent_file="${source_parent}/${source_name}.torrent"

# A .aria2 state file changes while aria2 runs. Do not hash it into a folder torrent.
if [[ -d "$source_path" && -e "$source_path/.aria2" ]]; then
    echo "Error: aria2 state file found inside the source directory:" >&2
    echo "  $source_path/.aria2" >&2
    echo "Stop aria2 and remove this state file before creating the torrent." >&2
    exit 1
fi

if [[ -e "$torrent_file" ]]; then
    echo "Error: output torrent already exists:" >&2
    echo "  $torrent_file" >&2
    echo "Rename or remove it before running this command again." >&2
    exit 1
fi

echo "=== Creating trackerless torrent ==="
echo "Source: $source_path"
echo "Output: $torrent_file"
echo

# No announce URL: trackerless.
# No private flag: DHT and PEX are allowed.
mktorrent \
    -o "$torrent_file" \
    "$source_path"


echo
echo "=== Torrent information (file list omitted) ==="

aria2c -S "$torrent_file" | awk '
    /^[[:space:]]*Files:[[:space:]]*$/ { exit }
    { print }
'


echo
echo "=== Starting integrity verification and seeding ==="
echo "BitTorrent listening port: TCP/UDP $BT_PORT"
echo "DHT listening port:        UDP $DHT_PORT"
echo

# aria2 must use the PARENT directory:
# - File torrent: parent contains the source file.
# - Folder torrent: parent contains the source folder.
aria2c \
    --dir="$source_parent" \
    --check-integrity=true \
    --enable-dht=true \
    --enable-peer-exchange=true \
    --dht-listen-port="$DHT_PORT" \
    --listen-port="$BT_PORT" \
    --seed-time="$SEED_TIME" \
    --seed-ratio="$SEED_RATIO" \
    -T "$torrent_file"
