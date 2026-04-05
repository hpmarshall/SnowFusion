"""
earthdata_credentials.py
Manages NASA Earthdata Login credentials stored in ~/.netrc.

This file is listed in .gitignore — DO NOT commit credentials to git.

Usage
-----
    from earthdata_credentials import ensure_earthdata_credentials
    ensure_earthdata_credentials()   # prompts once, then stores in ~/.netrc

The stored entry is used automatically by earthaccess (strategy="netrc")
and by any requests.Session that calls netrc for NSIDC hosts.
"""

import netrc
import getpass
import pathlib
import stat
import sys

EARTHDATA_HOST = "urs.earthdata.nasa.gov"


def ensure_earthdata_credentials() -> tuple[str, str]:
    """Return (username, password) for NASA Earthdata Login.

    Checks ~/.netrc first. If no entry exists, prompts the user interactively,
    writes the entry to ~/.netrc (creating the file if necessary), and sets
    permissions to 600 as required by most netrc parsers.

    Returns
    -------
    tuple[str, str]
        (username, password)
    """
    netrc_path = pathlib.Path.home() / ".netrc"

    # --- Try reading existing credentials ---
    if netrc_path.exists():
        try:
            rc = netrc.netrc(str(netrc_path))
            entry = rc.authenticators(EARTHDATA_HOST)
            if entry is not None:
                username, _, password = entry
                if username and password:
                    print(f"Loaded Earthdata credentials from {netrc_path} "
                          f"(user: {username})")
                    return username, password
        except netrc.NetrcParseError as exc:
            print(f"Warning: could not parse {netrc_path}: {exc}", file=sys.stderr)

    # --- Prompt for credentials ---
    print("\nNASA Earthdata Login required.")
    print(f"  Register at: https://urs.earthdata.nasa.gov")
    print(f"  Credentials will be stored in {netrc_path}\n")

    username = input("Earthdata username: ").strip()
    password = getpass.getpass("Earthdata password: ")

    if not username or not password:
        raise ValueError("Username and password must not be empty.")

    # --- Write to ~/.netrc ---
    _write_netrc_entry(netrc_path, EARTHDATA_HOST, username, password)
    print(f"\nCredentials saved to {netrc_path}")
    return username, password


def _write_netrc_entry(
    netrc_path: pathlib.Path,
    host: str,
    username: str,
    password: str,
) -> None:
    """Append (or replace) a machine entry in ~/.netrc."""
    # Read existing lines, stripping any old entry for this host
    lines: list[str] = []
    if netrc_path.exists():
        raw = netrc_path.read_text()
        lines = _strip_machine_block(raw, host)

    # Append new entry
    new_block = (
        f"\nmachine {host}\n"
        f"    login {username}\n"
        f"    password {password}\n"
    )
    lines.append(new_block)

    netrc_path.write_text("".join(lines))
    # Restrict permissions to owner read/write only (required by netrc)
    netrc_path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def _strip_machine_block(text: str, host: str) -> list[str]:
    """Return lines of text with any existing 'machine <host>' block removed."""
    output: list[str] = []
    skip = False
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if stripped.startswith("machine"):
            # Start of a new machine block — decide whether to skip it
            skip = stripped.split()[1] == host if len(stripped.split()) > 1 else False
        if not skip:
            output.append(line)
    return output


# ---------------------------------------------------------------------------
# Allow running directly: python earthdata_credentials.py
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    user, pw = ensure_earthdata_credentials()
    print(f"\nReady. Earthdata user: {user}")
