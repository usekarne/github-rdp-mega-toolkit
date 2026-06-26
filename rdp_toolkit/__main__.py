"""Module entry point so ``python -m rdp_toolkit`` works.

Delegates to :func:`rdp_toolkit.cli.main` and converts the returned exit
code into a :class:`SystemExit`.  We deliberately keep this file tiny —
all real CLI logic lives in :mod:`rdp_toolkit.cli`.
"""
from __future__ import annotations

import sys


def _run() -> int:
    """Import the CLI lazily and dispatch to ``main``.

    The lazy import ensures that ``python -m rdp_toolkit --version`` still
    works even when optional sibling subpackages are mid-build.
    """
    from .cli import main

    return main(sys.argv[1:])


if __name__ == "__main__":
    try:
        code = _run()
    except KeyboardInterrupt:
        # 130 is the conventional shell exit code for Ctrl-C.
        sys.stderr.write("\n[WARN] Interrupted by user.\n")
        code = 130
    sys.exit(code)
