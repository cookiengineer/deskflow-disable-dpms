# deskflow-disable-dpms

`LD_PRELOAD` shim that stops Deskflow from touching the X11 screen saver
and DPMS settings. Deskflow's `XWindowsScreenSaver` reads the current
`xset` state at startup and rewrites it on connect/disconnect and on
shutdown. This library stubs those calls so `xset -dpms` / `xset s off`
survive.

Port of the original
[barrier-disable-dpms](https://github.com/cookiengineer/barrier-disable-dpms)
hack.

## What Deskflow Calls

On Linux the offender is `XWindowsScreenSaver` in
[`src/lib/platform/XWindowsScreenSaver.cpp`](https://github.com/deskflow/deskflow/blob/v1.26.0/src/lib/platform/XWindowsScreenSaver.cpp):

```bash
$ nm -D --undefined-only /usr/bin/deskflow-core | grep -E 'DPMS|ScreenSaver'
                 U DPMSCapable
                 U DPMSDisable
                 U DPMSEnable
                 U DPMSForceLevel
                 U DPMSInfo
                 U DPMSQueryExtension
                 U XForceScreenSaver
                 U XGetScreenSaver
                 U XSetScreenSaver
```

The binary is a normal dynamically linked PIE (not setuid, no
capabilities) that resolves these through its GOT, so a preloaded object
wins symbol lookup. The Qt GUI (`deskflow`) only launches the core
process, so only that process needs the preload.

## How The Shim Works

- `DPMSQueryExtension()` and `DPMSCapable()` return `0`. Deskflow then
  keeps `m_dpms == false` and never calls any other DPMS entry point. The
  remaining DPMS calls are stubbed anyway, as defense in depth.
- `XSetScreenSaver()` and `XForceScreenSaver()` are no-ops.
- `XGetScreenSaver()` is intentionally passed through (read-only).
- The remaining hooks (`XSetSelectionOwner`, `XSetErrorHandler`,
  `XSetIOErrorHandler`, `XSetICFocus`, `XSetInputFocus`) pass through and
  exist only for tracing.

See [`x11hook/hook.c`](/x11hook/hook.c).

## Behavior Notes

These are the non-obvious behaviors that make the patch look flaky.

1. **`LD_PRELOAD` is per process and per machine.** It only wraps
   processes started with it set. The server and client are separate
   processes (often on separate machines); each needs the shim. Patching
   the client does not affect the server.

2. **Deskflow restores its captured state when it terminates.** At startup
   `XWindowsScreenSaver` records `m_timeout`, blanking settings, and DPMS
   enablement. Its destructor writes them back:

   ```cpp
   XWindowsScreenSaver::~XWindowsScreenSaver() {
     enableDPMS(m_dpmsEnabled);
     XSetScreenSaver(m_display, m_timeout, m_interval, m_preferBlanking, m_allowExposures);
     ...
   }
   ```

   So `systemctl --user stop/restart` re-applies the **startup** values
   *while the old process is terminating*. With the shim loaded those
   calls are `(BLOCKED)` and nothing changes. A hard `SIGKILL` skips the
   handler as well, but systemd uses `SIGTERM`.

3. **A running process cannot be protected retroactively.** If the
   process shutting down was started before the shim was in place, its
   termination handler uses the real X11 calls and resets the settings.
   That is a one-time event. After editing the unit, run `systemctl
   --user daemon-reload`; the next restart replaces the old process with
   a hooked one, and every restart after that is clean.

| process state | `xset` at start | you run `xset -dpms; xset s off` | then `systemctl --user stop/restart` |
|---|---|---|---|
| no `LD_PRELOAD` | 600 / enabled | off | **reset to 600 / enabled** |
| `LD_PRELOAD` | 600 / enabled | off | stays off (calls blocked) |

## Build

```bash
make          # builds x11hook/x11hook.so and tracer/main
make clean    # removes the build artifacts
```

## Install

```bash
./x11hook/install.sh deskflow-client.service   # or deskflow-server.service
```

This detects Arch (`pacman`) / Debian (`apt`), builds `x11hook.so`,
installs it as `/usr/local/lib/deskflow-disable-dpms.so`, and writes a
systemd user drop-in at
`~/.config/systemd/user/<service>.d/disable-dpms.conf`:

```ini
[Service]
Environment=LD_PRELOAD=/usr/local/lib/deskflow-disable-dpms.so
```

Apply it:

```bash
systemctl --user daemon-reload
systemctl --user restart deskflow-client.service
```

## Manual / GUI Use

The GUI passes its environment to the core child process:

```bash
env LD_PRELOAD=/usr/local/lib/deskflow-disable-dpms.so deskflow
```

Or run the core directly:

```bash
env LD_PRELOAD=/usr/local/lib/deskflow-disable-dpms.so \
    deskflow-core server --settings ~/.config/Deskflow/deskflow-server.conf
```

## Verify

Confirm a running process actually has the shim:

```bash
p=$(systemctl --user show -p MainPID --value deskflow-client.service)
tr '\0' '\n' < /proc/$p/environ | grep LD_PRELOAD
grep deskflow-disable-dpms /proc/$p/maps
```

Enable logging to watch intercepted calls:

```bash
X11HOOK_LOG=1 LD_PRELOAD=/usr/local/lib/deskflow-disable-dpms.so \
    deskflow-core server --settings ~/.config/Deskflow/deskflow-server.conf
# log: /tmp/x11-hook.log
```

On a healthy restart the log shows `XSetScreenSaver (BLOCKED)` during
shutdown and the `xset` state is unchanged. Logging is silent by default
because `XSetInputFocus` / `XSetICFocus` are hot paths.

## Tracer

[tracer/](/tracer/main.go) is a small Go helper that logs `exec` calls and
their parent, which is how the culprit was identified (nobody runs `xset`;
Deskflow uses the X11 API directly).

## Limitations

- A real `xscreensaver` instance is controlled via `SCREENSAVER` client
  messages (detected by `_SCREENSAVER_VERSION`), not via the functions
  above. That path is not blocked and does not affect the built-in saver
  this patch targets.
- The `org.freedesktop.ScreenSaver` / `org.gnome.SessionManager` D-Bus
  calls in `XDGPowerManager` only inhibit idle sleep and are left alone.
- Symbols are matched by name at load time; a statically linked X11 or
  symbol-versioned build would need a different approach.

## License

WTFPL
