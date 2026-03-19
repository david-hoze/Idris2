#include "zam_vm.h"

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <file.zamc>\n", argv[0]);
        return 1;
    }

    ZVM *vm = zam_load(argv[1]);
    if (!vm) {
        fprintf(stderr, "Failed to load %s\n", argv[1]);
        return 1;
    }

    vm->pc = vm->entry_point;
    zam_run(vm);
#ifdef ZAM_PROFILE
    extern void zam_print_profile(void);
    zam_print_profile();
#endif
    zam_free(vm);
    return 0;
}
