#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <X11/Xlib.h>
#include <X11/extensions/dpms.h>

// ---------- logging ----------
//
// Logging is opt-in so we don't spam /tmp or do disk I/O on the hot
// XSetInputFocus / XSetICFocus paths while deskflow is in use.
// Set X11HOOK_LOG=1 (or any value) to enable it.
static int log_enabled(void) {
    static int enabled = -1;
    if (enabled < 0) {
        enabled = (getenv("X11HOOK_LOG") != NULL);
    }
    return enabled;
}

static void log_call(const char *func) {
    if (!log_enabled()) {
        return;
    }
    FILE *f = fopen("/tmp/x11-hook.log", "a");
    if (f) {
        fprintf(f, "[HOOK] %s called\n", func);
        fclose(f);
    }
}

// ---------- DPMS hooks (BLOCKED) ----------
//
// Returning 0 from DPMSQueryExtension makes deskflow's
// XWindowsScreenSaver keep m_dpms == false, so it never touches DPMS
// at all. The remaining calls are stubbed anyway as defense-in-depth
// in case a future version queries them unconditionally.

Bool DPMSEnable(Display *dpy) {
    log_call("DPMSEnable (BLOCKED)");
    return 1; // pretend success
}

Bool DPMSDisable(Display *dpy) {
    log_call("DPMSDisable (BLOCKED)");
    return 1;
}

Bool DPMSForceLevel(Display *dpy, CARD16 level) {
    log_call("DPMSForceLevel (BLOCKED)");
    return 1;
}

Bool DPMSInfo(Display *dpy, CARD16 *level, BOOL *state) {
    log_call("DPMSInfo (FAKED)");
    if (level) *level = DPMSModeOn;
    if (state) *state = False;
    return 1;
}

Bool DPMSQueryExtension(Display *dpy, int *event_base, int *error_base) {
    log_call("DPMSQueryExtension (BLOCKED)");
    if (event_base) *event_base = 0;
    if (error_base) *error_base = 0;
    return 0; // pretend DPMS is unavailable
}

Bool DPMSCapable(Display *dpy) {
    log_call("DPMSCapable (BLOCKED)");
    return 0; // pretend the display can't do DPMS
}

// ---------- Screen saver (BLOCKED) ----------

int XSetScreenSaver(Display *dpy, int timeout, int interval,
                    int prefer_blanking, int allow_exposures) {
    log_call("XSetScreenSaver (BLOCKED)");
    return 0;
}

int XForceScreenSaver(Display *dpy, int mode) {
    log_call("XForceScreenSaver (BLOCKED)");
    return 1; // pretend success
}

// ---------- PASS-THROUGH hooks (tracing only) ----------

typedef int (*orig_XSetSelectionOwner_t)(Display*, Atom, Window, Time);
int XSetSelectionOwner(Display *dpy, Atom selection, Window owner, Time time) {
    log_call("XSetSelectionOwner");
    orig_XSetSelectionOwner_t orig = dlsym(RTLD_NEXT, "XSetSelectionOwner");
    return orig(dpy, selection, owner, time);
}

XErrorHandler XSetErrorHandler(XErrorHandler handler) {
    log_call("XSetErrorHandler");
    static XErrorHandler (*orig)(XErrorHandler) = NULL;
    if (!orig) orig = dlsym(RTLD_NEXT, "XSetErrorHandler");
    return orig(handler);
}

XIOErrorHandler XSetIOErrorHandler(XIOErrorHandler handler) {
    log_call("XSetIOErrorHandler");
    static XIOErrorHandler (*orig)(XIOErrorHandler) = NULL;
    if (!orig) orig = dlsym(RTLD_NEXT, "XSetIOErrorHandler");
    return orig(handler);
}

typedef void (*orig_XSetICFocus_t)(XIC);
void XSetICFocus(XIC ic) {
    log_call("XSetICFocus");
    orig_XSetICFocus_t orig = dlsym(RTLD_NEXT, "XSetICFocus");
    orig(ic);
}

typedef int (*orig_XSetInputFocus_t)(Display*, Window, int, Time);
int XSetInputFocus(Display *dpy, Window focus, int revert_to, Time time) {
    log_call("XSetInputFocus");
    orig_XSetInputFocus_t orig = dlsym(RTLD_NEXT, "XSetInputFocus");
    return orig(dpy, focus, revert_to, time);
}
