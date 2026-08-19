#ifndef CPTYShim_h
#define CPTYShim_h
#include <sys/types.h>

// Parent owns *master_fd and must close it. This function always closes its slave fd.
// Child inherits only descriptors 0/1/2, all connected to the echo-disabled PTY slave.
int az_pty_spawn(const char *path, char *const argv[], pid_t *child_pid, int *master_fd);
int az_pty_wait(pid_t pid, int *status, int options);
int az_pty_signal(pid_t pid, int signal_number);
int az_pty_set_nonblocking(int fd);
int az_pty_status_exited(int status);
int az_pty_status_exit_code(int status);
int az_pty_status_signaled(int status);
int az_pty_status_signal(int status);
int az_pty_read_process_args(pid_t pid, void *buffer, size_t *buffer_size);
#endif
