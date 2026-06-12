# scx-switch

A small toolkit for managing [sched_ext](https://github.com/sched-ext/scx) schedulers on Linux when you want **both** the distro-packaged version *and* a self-built version available, with a one-command switch between them — and a clean way to roll everything back.

Built and tested on **CachyOS / Arch Linux** but should work on any systemd distro with a sched_ext-capable kernel.

---

## What problem does this solve?

If you install `scx-scheds` from your distro, you get a stable set of schedulers in `/usr/bin`. But upstream `sched-ext/scx` moves fast — new schedulers (like `scx_flow`) and improvements land on `main` long before they reach your package manager.

You could just overwrite `/usr/bin/scx_*` with your own builds, but that:

- Creates conflicts with the package manager (`pacman -Qkk` will flag the files).
- Gets clobbered on the next `pacman -Syu`.
- Has no clean rollback.

**`scx-switch`** keeps both versions side by side:

| Source | Location | Managed by |
|---|---|---|
| `pacman` | `/usr/bin/scx_*` | your distro package |
| `repo`   | `/usr/local/bin/scx_*` | this toolkit, built from upstream `main` |

`/usr/local/bin` takes precedence in `PATH`, so the repo build is active by default — but a single `scx-switch pacman <sched>` falls back to the distro version, and `scx-switch revert` removes the shadow install entirely.

---

## Features

- **Three-state switching**: `pacman` ↔ `repo` ↔ `repo` (after `update`).
- **Persistent across reboots**: writes a real systemd unit, not a transient one.
- **No file conflicts with the package manager**: shadow-installs to `/usr/local/bin`, never touches `/usr/bin`.
- **Manifest-based revert**: knows exactly which files it put down, removes only those.
- **Coexists with `scx_loader`**: temporarily disables it while a manual scheduler is active, re-enables on `revert`.

---

## Requirements

- A kernel with `CONFIG_SCHED_CLASS_EXT=y` (recent CachyOS/Arch/Fedora/Ubuntu 25.04+ kernels qualify).
  ```bash
  test -d /sys/kernel/sched_ext && echo "sched_ext available"
  ```
- Build dependencies for `sched-ext/scx`:
  - **Arch / CachyOS**: `sudo pacman -S --needed rust cargo clang llvm libbpf bpf pahole libseccomp protobuf meson pkgconf`
  - **Ubuntu 25.04+**: see [scx INSTALL.md](https://github.com/sched-ext/scx/blob/main/INSTALL.md#ubuntu)
- The distro package, if available (provides the fallback "pacman" source):
  - **Arch / CachyOS**: `sudo pacman -S scx-scheds scx-tools`

---

## Quick start

```bash
# 1. Clone this toolkit
git clone https://github.com/nawka12/scx-switch ~/src/scx-switch

# 2. Bootstrap: clones sched-ext/scx, builds it, installs binaries + CLI
~/src/scx-switch/setup.sh

# 3. Switch to a scheduler — e.g. scx_flow from the upstream build
sudo scx-switch repo scx_flow

# 4. Check what's running
scx-switch status
```

That's it. The choice persists across reboots.

---

## Usage

```
scx-switch <command> [args]

  pacman <sched> [flags...]   Use /usr/bin/<sched> (distro package)
  repo   <sched> [flags...]   Use /usr/local/bin/<sched> (built from sched-ext/scx)
  update                      git pull + cargo build --release + reinstall the repo binaries.
                              If a repo-sourced scheduler is currently active, restart it
                              so it picks up the new build.
  status                      Show config, service state, and what the kernel reports
  off                         Stop scheduler, fall back to CFS/EEVDF, re-enable scx_loader
  revert                      Full teardown: remove unit, /usr/local/bin/scx_*,
                              re-enable scx_loader. Returns the system to a pacman-only state.
```

### Examples

```bash
# Use the bleeding-edge scx_flow from upstream
sudo scx-switch repo scx_flow

# Same, with a scheduler flag
sudo scx-switch repo scx_flow --debug

# Fall back to distro scx_rusty
sudo scx-switch pacman scx_rusty

# Pull new commits from upstream and rebuild
scx-switch update

# Check state
scx-switch status

# Temporarily stop (kernel uses CFS/EEVDF; config is kept)
sudo scx-switch off

# Full teardown — distro package becomes the only scx in the system
sudo scx-switch revert
```

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `SCX_REPO_DIR` | `$HOME/src/scx` | Where the `sched-ext/scx` source tree lives. Used by `update` and the install/revert helpers. |

---

## How it works

### Install layout

After `setup.sh`:

```
/usr/local/sbin/scx-switch                  # the CLI (only thing on PATH)
/usr/local/bin/scx_*                        # built schedulers (shadow /usr/bin)
/usr/local/bin/scxtop                       # built monitoring tool
/usr/local/share/scx-from-source/MANIFEST   # list of installed files, for clean revert
$SCX_REPO_DIR/scx-install.sh                # helpers, invoked by scx-switch
$SCX_REPO_DIR/scx-revert.sh                 #   through $SCX_REPO_DIR — not on PATH
$SCX_REPO_DIR/scx-rebuild.sh
```

After your first `sudo scx-switch repo <sched>`:

```
/etc/scx-switch.conf                        # BINARY= and FLAGS=
/etc/systemd/system/scx-switch.service      # the persistent unit
```

### Systemd unit (auto-generated)

```ini
[Unit]
Description=sched-ext scheduler (managed by scx-switch)
Conflicts=scx_loader.service
After=multi-user.target

[Service]
Type=simple
EnvironmentFile=/etc/scx-switch.conf
ExecStart=/bin/sh -c 'exec "$BINARY" $FLAGS'
KillSignal=SIGINT
Restart=on-failure
RestartSec=2
StartLimitBurst=3
StartLimitIntervalSec=60

[Install]
WantedBy=multi-user.target
```

The `Conflicts=scx_loader.service` line prevents both from being active at once. While `scx-switch.service` is enabled, `scx_loader.service` is **masked** (and gets unmasked + re-enabled by `scx-switch off`/`revert`). Masking matters: `scx_loader` is DBus-activated, so merely opening the `scx-manager` GUI would start it even when disabled — and via `Conflicts=` that would *silently* stop your scheduler and drop the kernel back to EEVDF. With the unit masked, that activation fails with an error instead.

### Comparison with other approaches

| Aspect | scx-switch | Overwrite `/usr/bin` | scx_loader (default) |
|---|---|---|---|
| Conflicts with package manager? | No | Yes | No |
| Survives `pacman -Syu`? | Yes | No (gets clobbered) | Yes |
| Supports schedulers not yet in scx_loader (e.g. `scx_flow`)? | Yes | Yes | No |
| Easy revert? | One command | Manual | n/a |
| Boots into chosen scheduler? | Yes | Depends | Yes (via scx_loader state) |

---

## Upgrading from an older scx-switch

Older versions only **disabled** `scx_loader.service` while a scheduler was active. That left it DBus-activatable: opening the `scx-manager` GUI would start it and silently stop your scheduler (kernel falls back to EEVDF). If you have an active config from an older version, either re-run `setup.sh` (it migrates automatically) or fix it by hand:

```bash
sudo systemctl mask scx_loader.service
```

`scx-switch status` warns when you're in this state.

---

## Uninstall

```bash
sudo scx-switch revert       # removes binaries and unit, re-enables scx_loader
sudo rm /usr/local/sbin/scx-switch
rm -rf ~/src/scx-switch ~/src/scx
```

---

## Caveats

- `scx-switch.service` and `scx_loader.service` are mutually exclusive (via `Conflicts=`). While `scx-switch` is the active mechanism, `scx_loader.service` is masked, so the `scx-manager` GUI and `scxctl` fail with an error — this is intentional: they DBus-activate `scx_loader`, which would otherwise silently kill your scheduler. Use `scx-switch off` or `revert` to give control back.
- The `repo` source builds the **entire** workspace by default (16+ schedulers and tools). First build can take 5–15 minutes; subsequent builds are incremental.
- If `pacman -Syu` updates `scx-scheds`, your `/usr/bin/scx_*` move forward but your `/usr/local/bin/scx_*` don't — run `scx-switch update` to refresh the repo build too.

---

## License

MIT. See [LICENSE](LICENSE).
