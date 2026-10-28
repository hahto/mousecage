#ifndef MOUSECAGE_CORE_H
#define MOUSECAGE_CORE_H

#include <stdbool.h>

typedef enum {
    ML_OK = 0,
    ML_ERR_TAP,     /* CGEventTapCreate failed: almost always missing Accessibility access */
    ML_ERR_THREAD,  /* pthread_create failed */
} ml_result;

/* Creates the event tap and starts the tap thread + window polling thread.
 * Safe to call again after a failure (only the missing parts are started).
 * After success further calls are no-ops. Not thread-safe: call from one thread. */
ml_result ml_start(const char *target_owner_name);

void ml_set_enabled(bool enabled);
bool ml_is_enabled(void);

/* True while the target window is frontmost (cursor is confined if enabled). */
bool ml_is_target_focused(void);

#endif
