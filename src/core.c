#include "core.h"

#include <ApplicationServices/ApplicationServices.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define TITLEBAR_HEIGHT  32.0
#define POLL_INTERVAL_MS 100

typedef struct {
    CFMachPortRef tap;
    CFStringRef target_owner_name;

    atomic_bool enabled;
    atomic_bool target_focused;
    pthread_mutex_t bounds_lock;
    CGRect bounds;

    /* Touched only on the tap thread. */
    double last_dx;
    double last_dy;
#ifdef ML_DEBUG
    int good_events;
    int bad_events;
#endif

    /* Touched only by ml_start(). */
    bool tap_thread_started;
    bool poll_thread_started;
} State;

/* Zero-initialised bounds are an empty rect, which the tap treats as "no target". */
static State g_state = {
    .enabled     = true,
    .bounds_lock = PTHREAD_MUTEX_INITIALIZER,
};

static double clamp(double value, double low, double high) {
    return value < low ? low : value > high ? high : value;
}


/*====== WINDOW POLLING ======*/

static bool window_layer(CFDictionaryRef window, int *layer) {
    CFNumberRef layer_ref = CFDictionaryGetValue(window, kCGWindowLayer);
    return layer_ref != NULL && CFNumberGetValue(layer_ref, kCFNumberIntType, layer);
}

static bool window_owner_is(CFDictionaryRef window, CFStringRef owner_name) {
    CFStringRef owner_ref = CFDictionaryGetValue(window, kCGWindowOwnerName);
    return owner_ref != NULL && CFEqual(owner_ref, owner_name);
}

/* Window bounds minus the title bar for normal windows. CGRectNull on failure. */
static CGRect window_content_bounds(CFDictionaryRef window, int layer) {
    CGRect bounds;
    CFDictionaryRef bounds_dict = CFDictionaryGetValue(window, kCGWindowBounds);
    if (bounds_dict == NULL || !CGRectMakeWithDictionaryRepresentation(bounds_dict, &bounds))
        return CGRectNull;

    if (layer == 0) {
        bounds.origin.y    += TITLEBAR_HEIGHT;
        bounds.size.height -= TITLEBAR_HEIGHT;
    }
    return bounds;
}

/* Walks windows front-to-back. Returns the target's bounds if it is the
 * frontmost window, CGRectNull if some other app's window is in front. */
static CGRect frontmost_target_bounds(CFArrayRef windows, CFStringRef target_name) {
    CFIndex count = CFArrayGetCount(windows);
    for (CFIndex index = 0; index < count; index++) {
        CFDictionaryRef window = CFArrayGetValueAtIndex(windows, index);

        int layer;
        if (!window_layer(window, &layer))
            continue;

        if (window_owner_is(window, target_name))
            return window_content_bounds(window, layer);  // any layer: fullscreen games sit above 0

        if (layer == 0)
            return CGRectNull;  // another app's normal window is in front
        // layer > 0 and not the target: menubar, Dock, notifications -> ignore
    }
    return CGRectNull;
}

static void poll_windows_once(State *state) {
    CFArrayRef windows = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (windows == NULL)
        return;

    CGRect bounds = frontmost_target_bounds(windows, state->target_owner_name);
    CFRelease(windows);

    pthread_mutex_lock(&state->bounds_lock);
    state->bounds = bounds;
    pthread_mutex_unlock(&state->bounds_lock);
    atomic_store(&state->target_focused, !CGRectIsNull(bounds));
}

static void *poll_thread_main(void *arg) {
    State *state = arg;
    pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);

    struct timespec interval = { .tv_sec = 0, .tv_nsec = POLL_INTERVAL_MS * 1000000L };
    for (;;) {
        poll_windows_once(state);
        nanosleep(&interval, NULL);
    }
    return NULL;
}


/*====== EVENT TAP ======*/

static CGEventRef on_mouse(CGEventTapProxy proxy, CGEventType type,
                           CGEventRef event, void *user_info) {
    (void)proxy;
    State *state = user_info;

#ifdef ML_DEBUG
    uint64_t start_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
#endif

    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(state->tap, true);
        return event;
    }

    if (!atomic_load(&state->enabled) || !atomic_load(&state->target_focused)) {
        state->last_dx = state->last_dy = 0;
        return event;
    }

    pthread_mutex_lock(&state->bounds_lock);
    CGRect bounds = state->bounds;
    pthread_mutex_unlock(&state->bounds_lock);
    if (CGRectIsEmpty(bounds)) {
        return event;
    }

    double dx = CGEventGetDoubleValueField(event, kCGMouseEventDeltaX) - state->last_dx;
    double dy = CGEventGetDoubleValueField(event, kCGMouseEventDeltaY) - state->last_dy;
    CGPoint cursor = CGEventGetLocation(event);
    CGPoint target = {
        clamp(cursor.x + dx, CGRectGetMinX(bounds), CGRectGetMaxX(bounds) - 1),
        clamp(cursor.y + dy, CGRectGetMinY(bounds), CGRectGetMaxY(bounds) - 1),
    };
    state->last_dx = target.x - cursor.x;
    state->last_dy = target.y - cursor.y;

#ifdef ML_DEBUG
    uint64_t before_warp_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
#endif
    CGWarpMouseCursorPosition(target);
#ifdef ML_DEBUG
    double after_warp_ns = (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - before_warp_ns) / 1e6;
#endif
#ifdef ML_DEBUG
    double elapsed_ms = (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start_ns) / 1e6;
    if (elapsed_ms >= 0.9) {
        state->bad_events += 1;
        printf("event %.3f ms, warp %.3f ms| bad events: %d/%d\n", elapsed_ms, after_warp_ns, state->bad_events, state->good_events);
    } else {
        state->good_events += 1;
    }
#endif

    return event;
}

/* The tap gets its own run loop so nothing on the main thread (UI, menus)
 * can ever delay a mouse event. */
static void *tap_thread_main(void *arg) {
    State *state = arg;
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);

    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, state->tap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    CGEventTapEnable(state->tap, true);

    CFRunLoopRun();
    return NULL;
}

static bool start_detached_thread(void *(*entry)(void *), void *arg) {
    pthread_t thread;
    if (pthread_create(&thread, NULL, entry, arg) != 0)
        return false;
    pthread_detach(thread);
    return true;
}


/*====== PUBLIC API ======*/

ml_result ml_start(const char *target_owner_name) {
    State *state = &g_state;

    if (!state->poll_thread_started) {
        if (state->target_owner_name != NULL)
            CFRelease(state->target_owner_name);   // uusintakutsu ennen poll-threadia
        state->target_owner_name = CFStringCreateWithCString(
            kCFAllocatorDefault, target_owner_name, kCFStringEncodingUTF8);
    }

    if (state->tap == NULL) {
        CGEventMask mask = CGEventMaskBit(kCGEventMouseMoved)
                         | CGEventMaskBit(kCGEventLeftMouseDragged)
                         | CGEventMaskBit(kCGEventRightMouseDragged)
                         | CGEventMaskBit(kCGEventOtherMouseDragged);

        state->tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                                      kCGEventTapOptionDefault, mask, on_mouse, state);
        if (state->tap == NULL)
            return ML_ERR_TAP;
    }

    if (!state->tap_thread_started) {
        if (!start_detached_thread(tap_thread_main, state))
            return ML_ERR_THREAD;
        state->tap_thread_started = true;
    }

    if (!state->poll_thread_started) {
        if (!start_detached_thread(poll_thread_main, state))
            return ML_ERR_THREAD;
        state->poll_thread_started = true;
    }

    return ML_OK;
}

void ml_set_enabled(bool enabled) {
    atomic_store(&g_state.enabled, enabled);
}

bool ml_is_enabled(void) {
    return atomic_load(&g_state.enabled);
}

bool ml_is_target_focused(void) {
    return atomic_load(&g_state.target_focused);
}
