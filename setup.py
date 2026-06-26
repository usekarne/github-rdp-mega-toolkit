"""Legacy setup.py shim for backwards compatibility.

All build configuration lives in ``pyproject.toml`` (PEP 517/518/621). This
file exists only so that callers invoking ``python setup.py ...`` directly
(e.g. very old pip versions or some CI tooling) continue to work.

The recommended way to build / install is::

    python3 -m build              # build sdist + wheel
    python3 -m pip install .      # install from source
"""
from setuptools import setup

setup()
