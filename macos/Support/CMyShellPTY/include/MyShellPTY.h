#ifndef MYSHELL_PTY_H
#define MYSHELL_PTY_H

#include <sys/types.h>

pid_t myshell_forkpty_exec(
    int *master_fd,
    const char *executable,
    char *const argv[],
    char *const envp[],
    const char *working_directory,
    unsigned short columns,
    unsigned short rows
);

int myshell_resize_pty(
    int master_fd,
    unsigned short columns,
    unsigned short rows
);

int myshell_exit_code(int wait_status);

#endif
