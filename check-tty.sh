#!/bin/bash
# Runs a command (default: ./build.sh, which includes the self-tests) with a
# pseudo-terminal as stdin/stdout, the way an interactive Terminal does, and
# fails if it hangs or exits non-zero.
#   ./check-tty.sh [--timeout SECONDS] [command ...]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT=900
if [ "${1:-}" = "--timeout" ]; then TIMEOUT="${2:?}"; shift 2; fi
[ $# -gt 0 ] || set -- ./build.sh
cd "$ROOT"
exec /usr/bin/python3 -I - "$TIMEOUT" "$@" <<'PY'
import os, pty, select, sys, time, signal
timeout = float(sys.argv[1]); cmd = sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
deadline = time.time() + timeout
tail = b""
while True:
    left = deadline - time.time()
    if left <= 0:
        os.kill(pid, signal.SIGKILL)
        print("\nTTY CHECK FAILED: no exit within %ds (hang)" % timeout); sys.exit(1)
    r, _, _ = select.select([fd], [], [], min(left, 1))
    if r:
        try: data = os.read(fd, 4096)
        except OSError: data = b""
        if not data: break
        sys.stdout.buffer.write(data); sys.stdout.flush(); tail = (tail + data)[-2000:]
_, status = os.waitpid(pid, 0)
code = os.waitstatus_to_exitcode(status)
print("\nTTY CHECK %s (exit %d)" % ("OK" if code == 0 else "FAILED", code))
sys.exit(code)
PY
