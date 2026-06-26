"""RDP runner submodule.

Re-exports the public API of :mod:`rdp_toolkit.rdp.runner` so callers can
simply do::

    from rdp_toolkit.rdp import start_session, connect_command
"""
from __future__ import annotations

from .runner import (
    CREDENTIALS_ARTIFACT,
    DEFAULT_REPO,
    DEFAULT_WORKFLOW,
    RunInfo,
    RunnerError,
    connect_command,
    kill,
    list_runs,
    parse_kv,
    rotate_password,
    start_session,
    stop_all,
)

__all__ = [
    "CREDENTIALS_ARTIFACT",
    "DEFAULT_REPO",
    "DEFAULT_WORKFLOW",
    "RunInfo",
    "RunnerError",
    "connect_command",
    "kill",
    "list_runs",
    "parse_kv",
    "rotate_password",
    "start_session",
    "stop_all",
]
