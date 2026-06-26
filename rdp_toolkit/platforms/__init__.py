"""Platform-specific setup helpers.

Each submodule (``kali``, ``windows``, ``android``) exposes functions used by
:func:`rdp_toolkit.platforms.installer.install_for_platform` to bootstrap an
RDP session on a particular OS family.

Public entry point:

    >>> from rdp_toolkit.platforms import install_for_platform
    >>> install_for_platform('kali')
"""
from __future__ import annotations

from .installer import install_for_platform

__all__ = ["install_for_platform"]
