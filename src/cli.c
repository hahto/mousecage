#include "core.h"

#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    const char *target_owner_name = argc > 1 ? argv[1] : "League Of Legends";

    switch (ml_start(target_owner_name)) {
    case ML_OK:
        break;
    case ML_ERR_TAP:
        fprintf(stderr, "Starting event tap failed! (Accessibility permission for this terminal?)\n");
        return 1;
    case ML_ERR_THREAD:
        fprintf(stderr, "Starting threads failed!\n");
        return 1;
    }

    printf("Confining cursor to \"%s\". Ctrl-C to quit.\n", target_owner_name);
    for (;;)
        pause();
}
