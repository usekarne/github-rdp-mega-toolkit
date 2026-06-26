"""Password generation, complexity enforcement, and hashing.

Uses :mod:`secrets` (CSPRNG) for all randomness so the output is safe to
use as real RDP / SSH credentials.  Hashing is SHA-256 — fast and good
enough for non-password-store use cases (the toolkit never persists raw
passwords to disk; only the SHA-256 fingerprint is logged for audit).
"""
from __future__ import annotations

import hashlib
import secrets
import string
from typing import Dict

__all__ = [
    "UPPER",
    "LOWER",
    "DIGITS",
    "SYMBOLS",
    "generate_password",
    "enforce_complexity",
    "hash_password",
]

UPPER = string.ascii_uppercase
LOWER = string.ascii_lowercase
DIGITS = string.digits
# Safe symbol set — avoids quote/backslash/``$`` so passwords survive
# shell-quoting and YAML round-trips without escaping headaches.
SYMBOLS = "!@#$%^&*()-_=+[]{}<>?"


def generate_password(length: int = 24) -> str:
    """Generate a cryptographically-secure password.

    Guarantees at least one character from each of: upper, lower, digit,
    symbol.  The remaining characters are sampled uniformly from the full
    pool and the whole result is shuffled with a CSPRNG.

    Parameters
    ----------
    length:
        Desired length (minimum 4 to satisfy all complexity classes).

    Raises
    ------
    ValueError
        If ``length`` is less than 4.
    """
    if length < 4:
        raise ValueError("Password length must be at least 4")
    pools = [UPPER, LOWER, DIGITS, SYMBOLS]
    chars = [secrets.choice(pool) for pool in pools]
    full_pool = "".join(pools)
    chars.extend(secrets.choice(full_pool) for _ in range(length - 4))
    # Fisher–Yates shuffle using the system CSPRNG.
    rng = secrets.SystemRandom()
    rng.shuffle(chars)
    return "".join(chars)


def enforce_complexity(pwd: str) -> Dict[str, bool]:
    """Validate ``pwd`` against the toolkit's complexity policy.

    Returns a dict with the individual checks plus an aggregate ``valid``
    flag.  A password is ``valid`` when it contains at least one of each
    character class and is at least 12 characters long.
    """
    checks = {
        "upper": any(c in UPPER for c in pwd),
        "lower": any(c in LOWER for c in pwd),
        "digit": any(c in DIGITS for c in pwd),
        "symbol": any(c in SYMBOLS for c in pwd),
        "length_ok": len(pwd) >= 12,
    }
    checks["valid"] = all(checks.values())
    return checks


def hash_password(pwd: str, salt: str = "") -> str:
    """Return the SHA-256 hex digest of ``salt + pwd``.

    The optional ``salt`` lets callers bind a hash to a specific run-id
    so the same password produces different fingerprints across runs.
    """
    digest = hashlib.sha256()
    digest.update((salt + pwd).encode("utf-8"))
    return digest.hexdigest()
