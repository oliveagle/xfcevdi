# XFCE VDI (using X2Go) + MetaTrader 5

Docker image for running [Debian](https://hub.docker.com/_/debian) + [XFCE](https://www.xfce.org/) accessible over [X2Go](https://wiki.x2go.org/), with **MetaTrader 5** pre-packaged and able to auto-install / auto-upgrade.

## Purpose

- Spin up a full Linux virtual desktop inside Docker (no VM), reachable via X2Go.
- MetaTrader 5 runs on Linux via Wine, installed into a per-user Wine prefix (`~/.mt5`), with automatic upgrade through the official web-installer.
- The whole stack is built on **Debian 12 (bookworm)**.

## Software stack

| Layer                     | Version / source                |
|---------------------------|---------------------------------|
| Base image                | `debian:bookworm-slim`          |
| Desktop                   | XFCE 4.18                       |
| Remote desktop            | X2Go 4.1 (server + session)     |
| Browser                   | Firefox ESR                     |
| Wine                      | WineHQ stable (bookworm)        |
| MetaTrader 5              | auto-installed from mt5setup.exe (last Docker layer) |
| Dev toolchain             | gcc, clang, cmake, ninja, valgrind, clang-format/tidy, pytest, shellcheck, etc. |

## MetaTrader 5 on Linux (why and how)

MetaTrader 5 does not ship a native Linux binary. The official install path is the Windows installer `mt5setup.exe` run under Wine, documented by MetaQuotes in
[Running MetaTrader 5 on Linux](https://www.mql5.com/zh/articles/625) and
[Installation on Linux](https://www.metatrader5.com/en/terminal/help/start_advanced/install_linux).

MT5 ships as a **web-installer** and auto-updates itself on every launch. Because it updates very frequently, this image puts **MT5 into the last Docker layer**:

1. Every lower layer (OS, desktop, Wine, dev toolchain) stays cached.
2. Rebuilding the image re-fetches only the MT5 installer, so the newest MT5 build is always picked up.
3. The installer script `/usr/local/bin/mt5-install` is idempotent and runs:
   - on **first container start** (`scripts/setup.sh`), installing MT5 into the new user's `~/.mt5` Wine prefix;
   - on **first launch** from the XFCE application menu (`metatrader5.desktop` → `/usr/local/bin/mt5-launch`);
   - **every 6 hours** via cron (`/etc/cron.d/mt5-autoupdate`), so a new build is picked up even if the user never reopens the terminal.

### How the installer works

| Script                     | Purpose                                                        |
|----------------------------|----------------------------------------------------------------|
| `/usr/local/bin/mt5-install`   | Download `mt5setup.exe` (and WebView2), run it with `/auto` under the user's Wine prefix, then record a stamp so the next run is a fast no-op. |
| `/usr/local/bin/mt5-autoupdate` | Wrap `mt5-install --force` with flock + logging; used by cron. |
| `/usr/local/bin/mt5-launch`     | Install (if missing), then launch `terminal64.exe` inside the X session. |

You can also trigger them manually from the user's shell:

```bash
mt5-install         # install or update (no-op if already up to date)
mt5-install --force # force a reinstall / upgrade
mt5-install --check # show current status
mt5                 # launch the terminal (installs first if needed)
```

Environment variables (all optional):

| Variable                  | Default                        | Description                             |
|---------------------------|--------------------------------|-----------------------------------------|
| `MT5_SETUP_URL`           | MetaQuotes CDN                 | Override if a mirror is needed.         |
| `MT5_INSTALL`             | `yes`                          | Install MT5 on first container start.   |
| `MT5_AUTOUPDATE`          | `yes`                          | Register the 6-hour cron upgrade.       |
| `MT5_INSTALL_WEBVIEW2`    | `yes`                          | Also install the WebView2 runtime.      |
| `MT5_CACHE_DIR`           | `/var/cache/mt5`               | Shared cache for the installer.         |

## Usage

### Docker

```sh
docker run --shm-size 2g -it --rm -p 2222:22 xfcevdi:dev
```

Or with a custom username and password:

```sh
docker run --shm-size 2g -it --rm -p 2222:22 -e USERNAME=trader -e PASS=secret xfcevdi:dev
```

### Docker Compose

```sh
docker compose up
```

Connect with the X2Go client to `localhost:2222`, user `trader` (or `user` by default), then launch **MetaTrader 5** from the applications menu.

## Development & testing

The full "build → lint → test" workflow is automated:

```sh
make lint      # shellcheck + bash -n on scripts/
make build     # build the container image
make test      # lint + build + MT5 layer check + runtime smoke test
make shell     # interactive shell inside the built image
```

Static test helpers (no container build required):

```sh
bash tests/test_dockerfile.sh   # verify bookworm stack and MT5 last layer
bash tests/test_mt5_layer.sh    # verify MT5 instructions are in the last layer
bash tests/test_ci.sh           # verify CI workflow shape
```

CI runs `lint`, `hadolint`, `make build`, the MT5 layer check, and the runtime smoke test on every push/PR.

## Configuration files

| File                              | Purpose                                    |
|-----------------------------------|--------------------------------------------|
| `configs/sources.list`            | Debian 12 mirror (USTC).                   |
| `configs/sources.list.tuna`       | Alternative Tsinghua mirror.               |
| `configs/x2go.list`               | X2Go repository (bookworm).                |
| `configs/metatrader5.desktop`     | XFCE application launcher entry for MT5.   |
| `configs/mt5-cron`                | Default MT5 upgrade cron entry.            |
| `scripts/mt5-install.sh`          | Idempotent MT5 installer / updater.        |
| `scripts/mt5-autoupdate.sh`       | Cron wrapper with flock + logging.         |
| `scripts/mt5-launch.sh`           | Launch (install if needed) MetaTrader 5.   |

## Licence

[GPL-3.0](LICENSE)
