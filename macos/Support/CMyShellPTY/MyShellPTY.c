#include "MyShellPTY.h"

#include <signal.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>
#include <util.h>

pid_t myshell_forkpty_exec(
    int *master_fd,
    const char *executable,
    char *const argv[],
    char *const envp[],
    const char *working_directory,
    unsigned short columns,
    unsigned short rows
) {
    struct winsize size = {
        .ws_row = rows,
        .ws_col = columns,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    pid_t child = forkpty(master_fd, NULL, NULL, &size);
    if (child != 0) {
        return child;
    }

    if (working_directory != NULL && chdir(working_directory) != 0) {
        _exit(126);
    }

    execve(executable, argv, envp);
    _exit(127);
}

int myshell_resize_pty(
    int master_fd,
    unsigned short columns,
    unsigned short rows
) {
    struct winsize size = {
        .ws_row = rows,
        .ws_col = columns,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    return ioctl(master_fd, TIOCSWINSZ, &size);
}

int myshell_exit_code(int wait_status) {
    if (WIFEXITED(wait_status)) {
        return WEXITSTATUS(wait_status);
    }
    if (WIFSIGNALED(wait_status)) {
        return 128 + WTERMSIG(wait_status);
    }
    return -1;
}
