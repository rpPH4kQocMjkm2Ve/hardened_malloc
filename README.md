# hardened-malloc

GrapheneOS [hardened_malloc](https://github.com/GrapheneOS/hardened_malloc) — packaged for system-wide preloading on Linux.

Builds both variants from source, plus a `libfake_rlimit.so` shim for GTK4/glycin compatibility.

## What gets installed

| File | Purpose |
|------|---------|
| `/usr/local/lib/libhardened_malloc.so` | Default variant — full hardening, for per-app use via bwrap `LD_PRELOAD` |
| `/usr/local/lib/libhardened_malloc-light.so` | Light variant — balanced, loaded system-wide via `/etc/ld.so.preload` |
| `/usr/local/lib/libfake_rlimit.so` | Intercepts `prlimit64`/`setrlimit` `RLIMIT_AS` calls to prevent crashes |
| `/etc/ld.so.preload` | Preloads `libfake_rlimit.so` + `libhardened_malloc-light.so` globally |

## Why fake_rlimit

GTK4 uses [glycin](https://gitlab.gnome.org/GNOME/glycin) for image loading, which sets `RLIMIT_AS` on its sandboxed loader processes. This is incompatible with hardened_malloc's large virtual memory reservation (~240 GB `PROT_NONE` guard regions). The shim intercepts `prlimit64(RLIMIT_AS)` and `setrlimit(RLIMIT_AS)` calls, returning success without applying the limit. All other resource limits are passed through unchanged.

## Compatibility

The light variant provides zero-on-free, slab canaries, and guard slabs. The default variant adds slot randomization, write-after-free checks, and slab quarantines.

Applications with custom allocators (Chromium/PartitionAlloc, Firefox/mozjemalloc) are incompatible and must have hardened_malloc disabled in their bwrap wrappers via `--ro-bind /dev/null /etc/ld.so.preload`.

## Configuration

Both files are installed and managed by the package:

- `/etc/ld.so.preload` — preloads `libfake_rlimit.so` + `libhardened_malloc-light.so`
- `/etc/sysctl.d/20-hardened-malloc.conf` — `vm.max_map_count = 1048576` for guard slabs

To use the default (stricter) variant system-wide instead of light, edit `/etc/ld.so.preload`:

```
/usr/local/lib/libfake_rlimit.so
/usr/local/lib/libhardened_malloc.so
```

## Install

### With gitpkg

```sh
gitpkg repo-add https://gitlab.com/fkzys
gitpkg install hardened-malloc
```

See [gitpkg](https://gitlab.com/fkzys/gitpkg) for details.

### Manually

```sh
make build
sudo make install
```

## Uninstall

### With gitpkg

```sh
gitpkg remove hardened-malloc
```

### Manually

```sh
sudo make uninstall
```

## Updating

```bash
# Check latest tag
git ls-remote --tags https://github.com/GrapheneOS/hardened_malloc.git \
    | grep -oP 'refs/tags/\K[0-9]{10}$' | sort -n | tail -5

# Update TAG in Makefile, commit, then:
gitpkg update hardened-malloc
# or manually:
make clean && make build && sudo make install
```

## Dependencies

- `base-devel` (`gcc`, `make`)
- `git`
