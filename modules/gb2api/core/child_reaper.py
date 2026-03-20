"""
Child process reaper (Linux/Unix).

When third-party libraries spawn subprocesses and do not `wait()` them properly,
the exited children become zombie processes (<defunct>) until the parent reaps.

This module installs a SIGCHLD handler that reaps all exited children with
os.waitpid(-1, WNOHANG) to prevent zombie accumulation in long-running services.
"""

from __future__ import annotations

import errno
import os
import signal
from typing import Callable, Optional, Union


_InstalledHandler = Union[int, Callable[[int, object], None], None]


def install_child_reaper(log: Optional[Callable[[str], None]] = None) -> bool:
    """
    Install a SIGCHLD handler to reap zombie processes.

    Returns True if a handler was installed, otherwise False.
    Safe to call multiple times; it will simply re-install the handler.
    """
    # Windows has no SIGCHLD; only do this on POSIX.
    if os.name != "posix":
        return False

    if not hasattr(signal, "SIGCHLD"):
        return False

    try:
        old_handler: _InstalledHandler = signal.getsignal(signal.SIGCHLD)
    except Exception:
        old_handler = None

    def _log(msg: str) -> None:
        if log:
            try:
                log(msg)
            except Exception:
                pass

    def _reap_all_children() -> None:
        # Reap all already-exited child processes (non-blocking).
        while True:
            try:
                pid, _status = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                # No child processes.
                return
            except OSError as e:
                if e.errno == errno.ECHILD:
                    return
                # Any other error: stop to avoid spinning.
                _log(f"[CHILD-REAPER] waitpid failed: {e}")
                return

            if pid == 0:
                return

    def _handler(signum: int, frame) -> None:
        # 1) First reap everything we can to prevent zombies.
        _reap_all_children()

        # 2) Chain previous handler (if it was a Python callable).
        try:
            if callable(old_handler):
                old_handler(signum, frame)
        except Exception:
            # Never let exceptions escape a signal handler.
            pass

    try:
        signal.signal(signal.SIGCHLD, _handler)
        return True
    except Exception as e:
        _log(f"[CHILD-REAPER] failed to install SIGCHLD handler: {e}")
        return False

