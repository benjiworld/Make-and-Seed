# Trackerless Torrent Creator and aria2 Seeder

`make_and_seed.sh` is a Bash utility for creating and seeding a **public, trackerless BitTorrent v1 torrent** from a single file or directory.

It combines:

- [`mktorrent`](https://github.com/Rudde/mktorrent) to create the `.torrent` metadata;
- [`aria2`](https://aria2.github.io/) to display torrent metadata, verify the local content, join the DHT, and seed the torrent.

The script is intended for files and directories that you are authorized to distribute.

## What the script does

Given exactly one source path, the script:

1. validates that the argument exists and is a regular file or directory;
2. resolves the absolute path with `realpath`;
3. creates `<source-name>.torrent` in the **parent directory** of the source;
4. creates the torrent without trackers and without the private flag;
5. invokes `aria2c -S` and prints the torrent metadata while omitting the potentially long file-list section;
6. verifies the local content with aria2;
7. starts trackerless seeding through DHT and peer exchange (PEX).

For a directory input, the torrent is deliberately written next to the directory, not inside it. This avoids accidentally adding the newly created `.torrent` file to the source tree being hashed.

## Requirements

This project targets Linux and requires:

| Requirement | Purpose |
|---|---|
| Bash | Runs the script. Bash 4+ is recommended. |
| `mktorrent` | Creates BitTorrent v1 `.torrent` files. |
| `aria2c` | Inspects, verifies, and seeds the torrent. |
| GNU `realpath` | Resolves the source path. Usually provided by GNU coreutils. |
| `awk` | Hides the file-list part of `aria2c -S` output. |
| Internet connection | Needed for DHT peer discovery while seeding/downloading. |

The script checks for `mktorrent`, `aria2c`, and `realpath` before it starts.

### Install prerequisites on Debian or Ubuntu

```bash
sudo apt update
sudo apt install aria2 mktorrent gawk coreutils
```

### Install prerequisites on Fedora

```bash
sudo dnf install aria2 mktorrent gawk coreutils
```

### Install prerequisites on Arch Linux

```bash
sudo pacman -S aria2 mktorrent gawk coreutils
```

Check that the commands are available:

```bash
command -v mktorrent
command -v aria2c
command -v realpath
```

## Installation

1. Save the script as `make_and_seed.sh`.
2. Make it executable:

```bash
chmod +x make_and_seed.sh
```

3. Optionally install it for the current user:

```bash
mkdir -p ~/.local/bin
cp make_and_seed.sh ~/.local/bin/make_and_seed
chmod +x ~/.local/bin/make_and_seed
```

Ensure `~/.local/bin` is on your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

To make that persistent in Bash, add the preceding line to `~/.bashrc`, then reload it:

```bash
source ~/.bashrc
```

## Usage

```bash
./make_and_seed.sh "/path/to/file-or-directory"
```

If installed under `~/.local/bin`:

```bash
make_and_seed "/path/to/file-or-directory"
```

Always quote paths containing spaces, parentheses, or special shell characters.

### Create and seed a single file

```bash
./make_and_seed.sh "/home/user/Downloads/archive.iso"
```

This produces:

```text
/home/user/Downloads/archive.iso.torrent
```

aria2 is started with:

```text
--dir=/home/user/Downloads
```

so it can find `archive.iso` during verification.

### Create and seed a directory

```bash
./make_and_seed.sh "/home/user/Downloads/MyFolder"
```

The resulting layout is:

```text
/home/user/Downloads/
├── MyFolder/
│   ├── document.pdf
│   └── data.bin
└── MyFolder.torrent
```

aria2 is started with the parent directory:

```text
--dir=/home/user/Downloads
```

This is required because the torrent's root entry is `MyFolder`.

## Torrent characteristics

The script invokes `mktorrent` without tracker, web-seed, or private-torrent options:

```bash
mktorrent -o "$torrent_file" "$source_path"
```

The produced torrent is therefore intended to be:

- **trackerless**: no announce URL is added;
- **public**: it is not marked private;
- **BitTorrent v1**: suitable for aria2;
- discoverable through **DHT** and peer exchange (**PEX**), provided participating clients support them.

Do not add mktorrent's private-torrent option if you need DHT/PEX discovery.

## Seed settings

The default script settings are:

```bash
DHT_PORT=5002
BT_PORT=5001
SEED_TIME=10080
SEED_RATIO=0.0
```

| Setting | Meaning |
|---|---|
| `DHT_PORT=5002` | aria2 listens for IPv4 DHT traffic on UDP port 5002. |
| `BT_PORT=5001` | aria2 listens for incoming BitTorrent TCP connections on port 5001. |
| `SEED_TIME=10080` | Seed for at most 10,080 minutes, or 7 days. |
| `SEED_RATIO=0.0` | No upload-ratio cap. |

aria2 stops when **either** a configured seeding condition is reached. With the supplied settings, the practical limit is the 7-day seed time.

### Seed indefinitely

To seed until you stop aria2 manually, remove or comment out:

```bash
SEED_TIME=10080
```

and remove this option from the final `aria2c` command:

```bash
--seed-time="$SEED_TIME"
```

Leave this option in place if there should be no ratio limit:

```bash
--seed-ratio="$SEED_RATIO"
```

Stop aria2 manually with `Ctrl+C`.

## Network and firewall configuration

Trackerless operation does not require port forwarding to function, but reachable listening ports usually improve peer connectivity.

If you control the firewall/router, allow or forward:

| Protocol | Port | Use |
|---|---:|---|
| TCP | 5001 | Incoming BitTorrent peer connections |
| UDP | 5002 | IPv4 DHT |

For example, using UFW:

```bash
sudo ufw allow 5001/tcp
sudo ufw allow 5002/udp
```

If your Internet connection uses CGNAT or you do not control the router, port forwarding may be unavailable. You can still seed and connect to reachable peers, but inbound connectivity may be reduced.

## Reading the output

Before seeding, aria2 performs a local integrity check. A successful result looks like:

```text
Verification finished successfully. file=/path/to/content
```

Then the status changes to something similar to:

```text
[#abcdef SEED(0.3) CN:4 SD:0 UL:12MiB(822MiB)]
```

| Field | Meaning |
|---|---|
| `SEED(...)` | The local content is complete and is being shared. |
| `CN:4` | Four peers are currently connected. |
| `SD:0` | No other complete seeders are currently known. |
| `UL:12MiB` | Current upload speed. |
| `(822MiB)` | Total uploaded data during this aria2 session. |

An intermediate verification line such as the following is normal:

```text
[Checksum:#abcdef 1.4GiB/2.0GiB(68%)]
```

It means aria2 is checking the existing local bytes against the torrent's piece hashes. It is not a checksum failure. A real failure contains text such as `Checksum error detected`.

## Safety checks and common errors

### Existing `.torrent` output

The script refuses to overwrite an existing output torrent:

```text
Error: output torrent already exists
```

Rename, move, or remove the old `.torrent` only after confirming that it is no longer needed. Then run the script again.

### `.aria2` state file inside a source directory

For a directory source, the script stops if it sees:

```text
<source-directory>/.aria2
```

A changing aria2 state file must not be part of a torrent because its contents can change after the hashes are calculated. Stop aria2 and remove that state file before creating a new torrent, after confirming that it is safe to do so.

### Checksum error during seeding

If aria2 reports a checksum error, do not continue seeding that torrent. Typical causes are:

- source files changed after the `.torrent` was created;
- the wrong `--dir` was used;
- a previous torrent was created from a different folder structure;
- temporary or state files were included in the source.

Create a new torrent only after checking the intended source tree and keeping it unchanged.

### Slow torrent creation

Creating a torrent requires reading every byte once to calculate piece hashes. For a single torrent, starting multiple creator processes does not split the work; it causes multiple full reads and is usually slower.

Very low hashing speed generally indicates a storage bottleneck, such as a USB drive, a network mount, antivirus scanning, or another process reading the same files.

## Inspect a torrent manually

The script already runs a shortened inspection. To view aria2's full file-list output manually:

```bash
aria2c -S "/path/to/file-or-directory.torrent"
```

For a long directory torrent, this may print every contained file.

## Notes

- Keep the original source files unchanged for the entire seeding session.
- Keep the `.torrent` file: other peers need it, unless you share an equivalent magnet link.
- Trackerless torrents may take longer to discover peers than torrents using reliable trackers.
- DHT/PEX availability depends on the peer's BitTorrent client and network configuration.
- Use this utility only for content you are permitted to distribute.


