"""Abstract base class for every tunnel provider.

A tunnel provider exposes a local TCP port (default 3389 — the RDP port) to
the public internet via a third-party relay service.  Each concrete provider
(serveo, localhost.run, cloudflare, localtunnel) implements ``start`` /
``stop`` / ``is_alive`` on top of the shared scaffolding defined here.

Pure stdlib only.  Cross-platform: graceful SIGTERM then SIGKILL on POSIX,
terminate/kill on Windows; process groups are used on POSIX so child
processes are also reaped.  Log capture is non-blocking: stdout/stderr are
read by daemon threads into an in-memory ring buffer that
:meth:`TunnelBase.parse_log_for_url` scans.
"""
from __future__ import annotations

import abc
import os
import re
import signal
import shutil
import subprocess
import threading
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Union

__all__ = ["TunnelBase"]


class TunnelBase(abc.ABC):
    """Common scaffolding for every tunnel provider.

    Subclasses implement the three abstract methods and use the concrete
    helpers (``_run_command``, ``_wait_for_url``, ``parse_log_for_url``,
    ``cleanup``) to spawn the relay process, wait for its URL to appear in
    the log output, and tear it down cleanly.
    """

    #: Default startup timeout in seconds — subclasses may override.
    startup_timeout: int = 50

    def __init__(self, name: str, local_port: int = 3389) -> None:
        """Construct a tunnel instance.

        ``name`` is a human-readable provider identifier (e.g. ``"serveo"``);
        ``local_port`` defaults to 3389 (the RDP port).
        """
        self.name: str = name
        self.local_port: int = local_port
        self.process: Optional[subprocess.Popen] = None
        self.url: Optional[str] = None
        self.host: Optional[str] = None
        self.port: Optional[int] = None
        self.tunnel_type: str = "tcp"
        self.bridge_required: bool = False
        self._log_buffer: List[str] = []
        self._log_lock = threading.Lock()
        self._stop_evt = threading.Event()

    @abc.abstractmethod
    def start(self, local_port: int = 3389) -> Dict[str, Union[str, int, bool]]:
        """Start the tunnel; return ``{url, host, port, type, ...}``."""

    @abc.abstractmethod
    def stop(self) -> None:
        """Stop the tunnel process gracefully, then forcefully."""

    @abc.abstractmethod
    def is_alive(self) -> bool:
        """Return ``True`` while the underlying process is running."""

    @property
    def info(self) -> Dict[str, Any]:
        """Return the current tunnel state as a dict (url/host/port/type/...)."""
        return {
            "provider": self.name,
            "url": self.url or "",
            "host": self.host or "",
            "port": self.port or 0,
            "type": self.tunnel_type,
            "bridge_required": self.bridge_required,
            "alive": self.is_alive(),
            "local_port": self.local_port,
        }

    def _run_command(
        self, cmd: Union[str, List[str]], capture: bool = True
    ) -> subprocess.Popen:
        """Spawn ``cmd`` via :class:`subprocess.Popen` and return the handle.

        When ``capture`` is True (default) stdout/stderr are piped into daemon
        reader threads that buffer the output for :meth:`parse_log_for_url`.
        A new POSIX session is created so the whole process group can be
        signalled on stop.
        """
        shell = isinstance(cmd, str)
        kwargs: Dict[str, Any] = dict(stdin=subprocess.DEVNULL, text=True, bufsize=1)
        if capture:
            kwargs["stdout"] = kwargs["stderr"] = subprocess.PIPE
        if os.name == "posix":
            kwargs["start_new_session"] = True
        self.process = subprocess.Popen(cmd, shell=shell, **kwargs)
        if capture and self.process.stdout and self.process.stderr:
            threading.Thread(target=self._reader, args=(self.process.stdout,), daemon=True).start()
            threading.Thread(target=self._reader, args=(self.process.stderr,), daemon=True).start()
        return self.process

    def _reader(self, stream: Any) -> None:
        """Background reader — buffers up to 1000 lines of process output."""
        try:
            for line in stream:
                if self._stop_evt.is_set():
                    break
                line = line.rstrip("\r\n")
                with self._log_lock:
                    self._log_buffer.append(line)
                    if len(self._log_buffer) > 1000:
                        del self._log_buffer[: len(self._log_buffer) - 500]
        except (ValueError, OSError):
            pass

    def _wait_for_url(
        self, timeout: int, checker: Callable[[], Optional[str]]
    ) -> Optional[str]:
        """Poll ``checker`` every 0.5 s up to ``timeout`` seconds; return first hit."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.process is not None and self.process.poll() is not None:
                return checker()
            url = checker()
            if url:
                return url
            time.sleep(0.5)
        return None

    def parse_log_for_url(
        self, regex: str, log_files: Optional[List[str]] = None
    ) -> Optional[str]:
        """Scan captured logs (and any ``log_files``) for ``regex``; return group(1) or the whole match."""
        pattern = re.compile(regex)
        sources: List[str] = []
        with self._log_lock:
            sources.extend(self._log_buffer)
        for path in log_files or []:
            try:
                sources.append(Path(path).read_text(errors="ignore"))
            except OSError:
                continue
        for blob in sources:
            for line in (blob.splitlines() or [blob]):
                m = pattern.search(line)
                if m:
                    return m.group(1) if m.groups() else m.group(0)
        return None

    def cleanup(self) -> None:
        """Release non-process resources (log buffer, reader threads)."""
        self._stop_evt.set()
        with self._log_lock:
            self._log_buffer.clear()

    def _signal_proc(self, proc: "subprocess.Popen", sig: int) -> None:
        """Send ``sig`` to ``proc``'s process group (POSIX) or ``proc`` (Windows)."""
        def _send() -> None:
            proc.terminate() if sig == signal.SIGTERM else proc.kill()
        try:
            if os.name == "posix":
                os.killpg(os.getpgid(proc.pid), sig)
            else:
                _send()
        except (ProcessLookupError, OSError):
            try:
                _send()
            except (ProcessLookupError, OSError):
                pass

    def _terminate_process(self) -> None:
        """SIGTERM the process group, then SIGKILL after 3 s."""
        proc = self.process
        if proc is None or proc.poll() is not None:
            self.process = None
            return
        self._signal_proc(proc, signal.SIGTERM)
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self._signal_proc(proc, signal.SIGKILL)
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
        self.process = None

    @staticmethod
    def _which(binary: str) -> Optional[str]:
        """Return absolute path to ``binary`` on ``$PATH`` or ``None``."""
        return shutil.which(binary)
