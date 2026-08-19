#include "CPTYShim.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>
extern char **environ;

int az_pty_spawn(const char *path, char *const argv[], pid_t *child_pid, int *master_fd) {
    int master = -1, slave = -1, result;
    struct termios settings;
    posix_spawn_file_actions_t actions;
    if (openpty(&master, &slave, NULL, NULL, NULL) != 0) return errno;
    if (tcgetattr(slave, &settings) != 0) { result = errno; goto fail; }
    settings.c_lflag &= ~(ECHO | ECHONL);
    if (tcsetattr(slave, TCSANOW, &settings) != 0) { result = errno; goto fail; }
    if (fcntl(master, F_SETFD, FD_CLOEXEC) != 0) { result = errno; goto fail; }
    if ((result = posix_spawn_file_actions_init(&actions)) != 0) goto fail;
    if ((result = posix_spawn_file_actions_adddup2(&actions, slave, STDIN_FILENO)) != 0) goto actions_fail;
    if ((result = posix_spawn_file_actions_adddup2(&actions, slave, STDOUT_FILENO)) != 0) goto actions_fail;
    if ((result = posix_spawn_file_actions_adddup2(&actions, slave, STDERR_FILENO)) != 0) goto actions_fail;
    if ((result = posix_spawn_file_actions_addclose(&actions, master)) != 0) goto actions_fail;
    if (slave > STDERR_FILENO && (result = posix_spawn_file_actions_addclose(&actions, slave)) != 0) goto actions_fail;
    result = posix_spawn(child_pid, path, &actions, NULL, argv, environ);
actions_fail:
    posix_spawn_file_actions_destroy(&actions);
    close(slave);
    if (result != 0) { close(master); return result; }
    *master_fd = master;
    return 0;
fail:
    if (slave >= 0) close(slave);
    if (master >= 0) close(master);
    return result;
}

int az_pty_wait(pid_t pid, int *status, int options) { return (int)waitpid(pid, status, options); }
int az_pty_signal(pid_t pid, int sig) { return kill(pid, sig); }
int az_pty_set_nonblocking(int fd) { return fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK); }
int az_pty_status_exited(int status) { return WIFEXITED(status); }
int az_pty_status_exit_code(int status) { return WEXITSTATUS(status); }
int az_pty_status_signaled(int status) { return WIFSIGNALED(status); }
int az_pty_status_signal(int status) { return WTERMSIG(status); }
int az_pty_read_process_args(pid_t pid, void *buffer, size_t *buffer_size) {
    int mib[3] = { CTL_KERN, KERN_PROCARGS2, pid };
    if (sysctl(mib, 3, buffer, buffer_size, NULL, 0) != 0) return errno;
    return 0;
}
