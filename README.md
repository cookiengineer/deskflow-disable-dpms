# How to Disable Deskflow Client/Server DPMS and XSetScreenSaver API calls

The problem with `deskflow-core` is that it messes up my DPMS config
and my screensaver settings. This project is an `LD_PRELOAD` patch that
stubs out every screen saver and DPMS function call Deskflow makes.

It is a port of the original Barrier
[barrier-disable-dpms](https://github.com/cookiengineer/barrier-disable-dpms)
hack. The behavior is identical: Deskflow's `XWindowsScreenSaver` rewrites
the X11 screen saver and DPMS state behind your back.

## Motivation

I am using `i3` and a separate `autostart.conf` file to use the
`exec --no-startup-id` calls to have autostart functionality
which starts all programs after I've been logged in. In order to
prevent my monitors from blanking out or powering off when I'm
not active or watching a video, I'm specifically disabling
DPMS and the screensaver via `xset`.

```bash
# disable all dpms settings
exec --no-startup-id xset dpms 0 0 0
exec --no-startup-id xset -dpms

# screensaver after 15 minutes
exec --no-startup-id xset s 900 900

# disable screensaver
exec --no-startup-id xset s off
```

## The Problem

However, Deskflow as a program is too stupid to realize that when
I move my mouse on my host system that I actually want to continue
to use my other system's connected monitors without them flickering
every couple minutes like a damn epilepsy inducing art installation.

There used to be a setting to disable this behavior, but the
maintainers removed it.

## Tracing The Culprit

I was almost losing my mind trying to figure out where the `xset`
calls come from. I've built a little helper program for that in the
[tracer](/tracer/main.go) folder.

Usage of that program is simple, for example to intercept `xset`
binary execution calls:

- Rename the original `/usr/bin/xset` to `/usr/bin/xset.real`
- Copy the built `/tracer/main` to `/usr/bin/xset`
- Use `watch cat /tmp/xset.log` to get parent and process info

Turns out, `xset` was not called from anywhere. The culprit was
`deskflow-core` executing the calls directly via the X11 API instead
of relying on `xset` for that. On Linux the relevant implementation is
`XWindowsScreenSaver` in
[`src/lib/platform/XWindowsScreenSaver.cpp`](https://github.com/deskflow/deskflow/blob/v1.26.0/src/lib/platform/XWindowsScreenSaver.cpp):

```bash
> nm -D --undefined-only /usr/bin/deskflow-core | grep -E 'DPMS|ScreenSaver'
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

Note: `deskflow` (the Qt GUI) only launches `deskflow-core`, so the
preload only needs to reach the `deskflow-core` process.

## Stubbing DPMS and XSet Function Calls

Remember the old [CVE-2009-0641](https://nvd.nist.gov/vuln/detail/CVE-2009-0641)
that showed a technique to implement privilege escalation for binaries
that don't drop their rights directly to `nobody` after they've done
something via `setuid(0)`?

Well, that technique allows to override pretty much all shared library
symbols. And that's what we're going to do, so that `deskflow-core`
only does nothing when it tries to mess with our DPMS and Screen Saver
settings.

`deskflow-core` is a normal dynamically linked PIE (not setuid, no
capabilities) that resolves these symbols through its GOT
(`-fno-plt` / `R_X86_64_GLOB_DAT`), so a preloaded library wins the
symbol lookup.

## x11hooks.so Function Call Blocker

So our little [hook.c](/x11hook/hook.c) library does nothing more
than to return the expected signature, and to do nothing, essentially
stubbing the API.

The most important trick is to make `DPMSQueryExtension()` and
`DPMSCapable()` return `0`. Deskflow then keeps `m_dpms == false` and
never calls any other DPMS function in the first place. The remaining
DPMS calls are stubbed anyway as defense-in-depth:

```c
Bool DPMSQueryExtension(Display *dpy, int *event_base, int *error_base) {
    log_call("DPMSQueryExtension (BLOCKED)");
    if (event_base) *event_base = 0;
    if (error_base) *error_base = 0;
    return 0; // pretend DPMS is unavailable
}
```

The built-in X screen saver is blocked via `XSetScreenSaver()` and
`XForceScreenSaver()`:

```c
int XSetScreenSaver(Display *dpy, int timeout, int interval,
                    int prefer_blanking, int allow_exposures) {
    log_call("XSetScreenSaver (BLOCKED)");
    return 0;
}

int XForceScreenSaver(Display *dpy, int mode) {
    log_call("XForceScreenSaver (BLOCKED)");
    return 1;
}
```

## Building

Build both the hook and the tracer from the project root:

```bash
make          # builds x11hook/x11hook.so and tracer/main
make clean    # removes the build artifacts
```

## Installation

The [install.sh](/x11hook/install.sh) script detects Arch Linux
(`pacman`) and Debian/Ubuntu (`apt`), builds `x11hook.so`, installs it
as `/usr/local/lib/deskflow-disable-dpms.so`, and writes a systemd user
drop-in for the deskflow service:

```bash
> ./install.sh
# or, if your service is named differently:
> ./install.sh deskflow-client.service
```

This creates
`~/.config/systemd/user/deskflow-server.service.d/disable-dpms.conf`:

```ini
[Service]
Environment=LD_PRELOAD=/usr/local/lib/deskflow-disable-dpms.so
```

Then apply it:

```bash
systemctl --user daemon-reload
systemctl --user restart deskflow-server.service
```

## Manual Usage

If you launch the GUI instead of the service, export the preload
before starting it. The GUI passes its environment on to the
`deskflow-core` child process:

```bash
env LD_PRELOAD=/usr/local/lib/deskflow-disable-dpms.so deskflow
```

Or run the core directly:

```bash
env LD_PRELOAD=/usr/local/lib/deskflow-disable-dpms.so \
    deskflow-core server --settings ~/.config/Deskflow/deskflow-server.conf
```

## Debugging

Logging is opt-in and silent by default so the hot input paths
(`XSetInputFocus`, `XSetICFocus`) don't spam `/tmp`. Set
`X11HOOK_LOG=1` to log every intercepted call to `/tmp/x11-hook.log`:

```bash
X11HOOK_LOG=1 LD_PRELOAD=/usr/local/lib/deskflow-disable-dpms.so \
    deskflow-core server --settings ~/.config/Deskflow/deskflow-server.conf
```

## Known Limitations

- If an actual `xscreensaver` instance is running, Deskflow detects its
  window (`_SCREENSAVER_VERSION`) and talks to it with `SCREENSAVER`
  `ACTIVATE`/`DEACTIVATE` client messages and synthetic motion events.
  That path is not blocked by this hook. It is irrelevant for the
  `xset`-based built-in screen saver this patch targets.
- The `org.freedesktop.ScreenSaver` / `org.gnome.SessionManager` D-Bus
  calls in `XDGPowerManager` only inhibit/enable *idle sleep*; they do
  not blank monitors, so they are intentionally left alone.
- Functions are matched by name at preload time. A future Deskflow
  build that statically links X11 or uses symbol versioning would need
  a different approach.

## License

WTFPL
