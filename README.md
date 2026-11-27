# Easy Minecraft Server Installer

A small Bash/batch installer that creates a ready-to-run Minecraft server in a new folder. It asks for a name, version, mod loader, and memory, then downloads the official files.

## Quick start

Linux:

```bash
chmod +x install-server.sh
./install-server.sh
```

Show help without installing: `./install-server.sh --help`.

Do not run as root; the installer refuses it.

Windows:

```bat
install-server.bat
```

Show help without installing: `install-server.bat --help`.

Start the server:

```bash
cd <server-name>
./run.sh
```

On Windows, use `run.bat` instead.

The installer writes `install-server-<server-name>.log` in the server folder. Forge/NeoForge also create their own installer logs.

## Requirements

- **Linux:** `bash`, `curl`, `tar`, a non-root user, and HTTPS access.
- **Windows:** Windows 10/11, `curl.exe`, and PowerShell 5.1.
- **Java:** 17/21/25 depending on the Minecraft version. If Java is missing or too old, the installer can download a local Temurin JDK.

The automatic JDK download supports x64 and aarch64.

## Versions

- **Linux and Windows:** Minecraft `1.18.2` to `26.x`; older versions and snapshots are excluded.

Loaders: Vanilla, Fabric, Forge, and NeoForge. Unsupported loader/version combinations stop with a clear error.

## Java

The installer uses the system Java when it is recent enough. Otherwise, it offers a local Temurin JDK:

- Linux: Java 17, 21, or 25, extracted to `<server>/.jdk`
- Windows: Java 17, 21, or 25, extracted to `<server>\.jdk\home`
- Used only by that server; nothing is installed system-wide
- Deleted with the server folder, not with `world/` alone
- Verified with SHA-256

If you decline the JDK download, the installer cancels.

## Security

- Downloads come from official HTTPS sources; both installers reject non-HTTPS URLs and redirects.
- Server files are checked with SHA-1 when the source provides one.
- No `sudo`; Linux refuses root and only writes to the new server folder and a temporary directory.
- Both installers ask for EULA acceptance and write `eula=true` only after acceptance.
- Forge/NeoForge installers run locally. Only use trusted mods and plugins.

## Disclaimer

This is an unofficial community tool. It is not affiliated with Mojang, Microsoft, FabricMC, MinecraftForge, NeoForged, or Adoptium.

## License

This project is licensed under the MIT License. Feel free to use, modify, and distribute it!
