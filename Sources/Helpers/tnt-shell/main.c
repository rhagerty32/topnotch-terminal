#include <dlfcn.h>
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

extern char **environ;

static pid_t g_child = 0;

static void forward_signal(int sig) {
    if (g_child > 0) {
        kill(g_child, sig);
    }
}

static void disclaim(posix_spawnattr_t *attr) {
    typedef int (*fn)(posix_spawnattr_t *, int);
    fn setdisclaim = (fn)dlsym(RTLD_DEFAULT, "responsibility_spawnattrs_setdisclaim");
    if (setdisclaim == NULL) {
        setdisclaim = (fn)dlsym(RTLD_DEFAULT, "posix_spawnattr_setdisclaimresponsibility_np");
    }
    if (setdisclaim != NULL) {
        (void)setdisclaim(attr, 1);
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "usage: tnt-shell <program> [args...]\n");
        return 127;
    }

    posix_spawnattr_t attr;
    if (posix_spawnattr_init(&attr) != 0) {
        perror("posix_spawnattr_init");
        return 127;
    }
    (void)posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    disclaim(&attr);

    int err = posix_spawn(&g_child, argv[1], NULL, &attr, argv + 1, environ);
    posix_spawnattr_destroy(&attr);
    if (err != 0) {
        errno = err;
        perror("posix_spawn");
        return 127;
    }

    struct sigaction sa = {0};
    sa.sa_handler = forward_signal;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    sigaction(SIGHUP, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGQUIT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGTSTP, &sa, NULL);

    signal(SIGTTOU, SIG_IGN);
    signal(SIGTTIN, SIG_IGN);
    (void)tcsetpgrp(STDIN_FILENO, g_child);

    int status = 0;
    pid_t waited;
    do {
        waited = waitpid(g_child, &status, 0);
    } while (waited < 0 && errno == EINTR);

    if (waited < 0) {
        return 127;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        signal(WTERMSIG(status), SIG_DFL);
        raise(WTERMSIG(status));
    }
    return 1;
}
