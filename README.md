# Easy Minecraft Server Installer

A small, dependency-light installer that creates a ready-to-run Minecraft server in a new folder. It is available as a Bash script for Linux and a batch script for Windows.

It asks for a server name, a Minecraft release, a mod loader, and the maximum memory to allocate, then downloads the correct files from official sources and prepares the server directory.

## Features

- Vanilla, Fabric, Forge, and NeoForge support
- Release versions only (snapshots excluded)
- Correct server or installer downloaded from official sources
- Linux and Windows installers (`install-server.sh` and `install-server.bat`)
- Tab completion for versions and mod loaders on Linux
- Java detection, with an optional local Temurin JDK download
- SHA-256 verification for downloaded JDKs
- Configurable maximum server memory, written to `run.sh`/`run.bat` or `user_jvm_args.txt`
- SHA-1 verification for server files when the source provides one
- Creates `eula.txt` and a `run.sh` or `run.bat` launcher
- Clear errors for unsupported version/loader combinations
- Nothing is bundled: everything is fetched on demand

## Requirements

### Linux

- `bash`
- `curl`
- `tar` (only when the automatic JDK download is used)
- Java 8, 11, 17, 21, or 25 depending on the Minecraft version, or accept the local JDK download

### Windows

- Windows 10 or 11
- `curl.exe` (included with Windows 10 1803 and later)
- PowerShell 5.1 (included with Windows 10 and 11)
- Java 8, 11, 17, 21, or 25 depending on the Minecraft version, or accept the local JDK download

The automatic JDK download supports Linux and Windows on x64 and aarch64.

## Usage

### Linux

```bash
chmod +x install-server.sh
./install-server.sh
```

### Windows

Double-click `install-server.bat`, or run it from Command Prompt:

```bat
install-server.bat
```

You will be prompted for:

1. Server name (used as the folder name)
2. Minecraft version
3. Mod loader
4. Maximum server memory in GB (default: 2)

Review the summary, confirm, and the server is created in the current directory.

Start it with:

```bash
cd <server-name>
./run.sh
```

On Windows:

```bat
cd <server-name>
run.bat
```

## Supported versions

Releases from 1.8.9 and 1.16 through the latest 26.x releases. Snapshots are excluded. The installer validates the version against a built-in release list.

Examples:

- `1.8.9`
- `1.16` - `1.16.5`
- `1.20` - `1.20.6`
- `1.21` - `1.21.11`
- `26.1` - `26.3`

## Mod loaders

| Loader   | Source         | Notes                                |
| -------- | -------------- | ------------------------------------ |
| Vanilla  | Mojang         | Official server jar                  |
| Fabric   | FabricMC       | Downloads the Fabric server launcher |
| Forge    | MinecraftForge | Classic modding platform             |
| NeoForge | NeoForged      | Modern Forge fork; 1.20.1+           |

Some loader/version combinations are not published by the loader authors. The installer detects this and stops with a clear error instead of downloading something invalid.

## Java

The installer detects the installed Java version. If it is missing or too old for the selected Minecraft version, it offers to download a local Temurin JDK into the server folder:

- Temurin LTS builds (8, 11, 17, 21, 25)
- Downloaded from the Adoptium API
- SHA-256 checksum verification
- Linux: extracted to `<server>/.jdk`
- Windows: extracted to `<server>\.jdk\home`
- The generated `run.sh`/`run.bat` and the Forge/NeoForge installer use this local JDK

If you decline the download, the installer cancels without creating the server.

## What gets created

```text
<server-name>/
├── eula.txt
├── run.sh (Linux) or run.bat (Windows)
└── <server or installer jar>
```

When a local JDK is used, it is stored in `.jdk/` on Linux or `.jdk\home` on Windows.

For Forge and NeoForge, the installer creates the usual libraries and launch scripts. On Windows, `run.bat` is used; when a local JDK is selected, it wraps the Forge/NeoForge launcher so the bundled Java is used.

## Security notes

- Files are downloaded over HTTPS from official sources: Mojang, FabricMC, MinecraftForge, NeoForged, and Adoptium.
- The optional JDK download is verified against its SHA-256 checksum.
- The installer does not use `sudo` and only writes to the new server folder and a temporary directory.
- On Windows, PowerShell is used for JSON parsing, checksums, and ZIP extraction.
- Forge and NeoForge installers are executed locally; this is required by those loaders.
- The installer writes `eula=true`, which means you accept the Minecraft EULA. Make sure you comply with it.
- Mods and plugins run with your user's permissions. Only use trusted ones and do not run the server as root.

## Disclaimer

This is an unofficial community tool. It is not affiliated with Mojang, Microsoft, FabricMC, MinecraftForge, NeoForged, or Adoptium.

## License

This project is licensed under the MIT License. Feel free to use, modify, and distribute it!
