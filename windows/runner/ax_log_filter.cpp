#include "ax_log_filter.h"

#include <fcntl.h>
#include <io.h>

#include <cstdio>
#include <cstring>
#include <thread>

namespace {

// Matched against the start of each line. Deliberately narrow: every other
// engine, plugin and Dart message still reaches the console.
constexpr char kSuppressed[] = "Failed to update ui::AXTree";

// A duplicate of the original stderr, kept open so the pump can still reach the
// console after stderr itself has been pointed at the pipe.
int g_console_stderr = -1;

// Forwards everything the app writes to stderr, minus the suppressed lines.
//
// Runs until the process exits. It must never return while stderr points at the
// pipe: with nobody draining it, the 64KB buffer would fill and the next log
// call would block whichever thread made it.
void PumpStderr(FILE* pipe) {
  char line[2048];
  while (fgets(line, sizeof(line), pipe) != nullptr) {
    if (std::strstr(line, kSuppressed) != nullptr) {
      continue;
    }
    _write(g_console_stderr, line,
           static_cast<unsigned int>(std::strlen(line)));
  }
  fclose(pipe);
}

}  // namespace

void InstallAXTreeLogFilter() {
  const int stderr_fd = _fileno(stderr);
  if (stderr_fd < 0) {
    return;  // No console attached, so there is nothing to filter.
  }

  int pipe_fds[2];
  if (_pipe(pipe_fds, 1 << 16, _O_BINARY) != 0) {
    return;
  }

  // Wrap the read end before redirecting anything. Failing after the redirect
  // would leave stderr pointing at a pipe with no reader.
  FILE* reader = _fdopen(pipe_fds[0], "r");
  if (reader == nullptr) {
    _close(pipe_fds[0]);
    _close(pipe_fds[1]);
    return;
  }

  g_console_stderr = _dup(stderr_fd);
  if (g_console_stderr < 0 || _dup2(pipe_fds[1], stderr_fd) != 0) {
    if (g_console_stderr >= 0) {
      _close(g_console_stderr);
      g_console_stderr = -1;
    }
    fclose(reader);
    _close(pipe_fds[1]);
    return;
  }
  _close(pipe_fds[1]);

  // Unbuffered, so each log call arrives as one write and fgets sees whole
  // lines rather than a half-filled buffer split mid-message.
  setvbuf(stderr, nullptr, _IONBF, 0);

  std::thread(PumpStderr, reader).detach();
}
