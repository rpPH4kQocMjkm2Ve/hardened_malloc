#define _GNU_SOURCE
#include <stddef.h>
#include <dlfcn.h>
#include <unistd.h>
#include <sys/resource.h>
#include <sys/syscall.h>

int prlimit64(__pid_t pid, enum __rlimit_resource resource,
              const struct rlimit64 *new_limit, struct rlimit64 *old_limit) {
    if (resource == RLIMIT_AS && new_limit != NULL) {
        if (old_limit) {
            return syscall(SYS_prlimit64, pid, resource, NULL, old_limit);
        }
        return 0;
    }
    return syscall(SYS_prlimit64, pid, resource, new_limit, old_limit);
}

int setrlimit(__rlimit_resource_t resource, const struct rlimit *rlim) {
    if (resource == RLIMIT_AS)
        return 0;
    static int (*real_setrlimit)(__rlimit_resource_t, const struct rlimit *) = NULL;
    if (!real_setrlimit)
        real_setrlimit = dlsym(RTLD_NEXT, "setrlimit");
    return real_setrlimit(resource, rlim);
}
