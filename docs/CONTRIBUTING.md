# Contributing

> Thanks for your interest in contributing to the GitHub RDP Mega Toolkit!
> This document covers the development workflow, code standards, commit
> conventions, and pull request process.

## Quick Reference

```bash
# 1. Fork + clone
git clone https://github.com/<your-username>/github-rdp-mega-toolkit.git
cd github-rdp-mega-toolkit
git remote add upstream https://github.com/usekarne/github-rdp-mega-toolkit.git

# 2. Create a feature branch
git checkout -b feat/add-persistent-tunnel-url

# 3. Make your changes, test locally
python3 -m py_compile rdp_toolkit/**/*.py
python3 -m rdp_toolkit doctor
python3 -m rdp_toolkit --help

# 4. Commit (Conventional Commits — see below)
git add .
git commit -m "feat(tunnel): support persistent URLs on localtunnel"

# 5. Rebase on latest upstream
git fetch upstream
git rebase upstream/main

# 6. Push + open PR
git push -u origin feat/add-persistent-tunnel-url
# Then open a PR on GitHub targeting `main`.
```

## Development Environment

### Prerequisites

- Python 3.10+ (`python3 --version`)
- `pip` (or your distro's equivalent)
- Git 2.20+
- (Optional) Docker 20.10+ for VM testing
- (Optional) `cloudflared` for tunnel testing
- (Optional) A GitHub PAT with `repo`+`workflow` scopes for end-to-end testing

### Setup

```bash
# Create a venv (recommended)
python3 -m venv .venv
source .venv/bin/activate

# Install runtime + dev deps
pip install -r requirements.txt
pip install build twine pylint black

# Install the package in editable mode
pip install -e .

# Verify
rdp-toolkit --version
rdp-toolkit doctor
```

### Running from a git checkout (no install)

The `scripts/rdp-toolkit` launcher auto-detects a local `rdp_toolkit/`
directory and prepends it to `PYTHONPATH`. So you can do:

```bash
./scripts/rdp-toolkit doctor
./scripts/rdp-toolkit --help
```

…without ever running `pip install`. Useful for quick iteration.

## Code Standards

### Style

- **PEP 8** with one exception: line length is **100 chars**, not 79.
- **`from __future__ import annotations`** at the top of every module —
  enables PEP 604 (`X | Y`) syntax even on 3.10.
- **Explicit `__all__`** at the top of every module — controls `from x import *`.
- **Type hints** on every public function. Internal helpers can skip them.
- **Docstrings** on every public class and function (Google style preferred).

### Tooling

```bash
# Format
black --line-length 100 rdp_toolkit/

# Lint
pylint rdp_toolkit/ --disable=too-many-arguments,too-many-locals,too-many-branches,too-many-statements,line-too-long

# Build (verify wheel builds cleanly)
python3 -m build
```

The `pyproject.toml` already has the matching `[tool.black]` and
`[tool.pylint."MESSAGES CONTROL"]` sections.

### Imports

- Standard library first, then third-party, then local. One blank line
  between groups.
- Lazy imports inside CLI handlers — keeps `--help` fast and resilient
  when a sibling subpackage has an issue.
- Avoid `from x import *` — use explicit `__all__` instead.

### Error handling

- Never raise raw `Exception` — use a specific subclass (`RunnerError`,
  `VMError`, `TunnelError`, etc.).
- Catch broadly (`except Exception`) only at trust boundaries (CLI
  handlers, HTTP wrappers) and always log the exception.
- Use `logging.getLogger(__name__)` (`_LOG`) for debug/diagnostic output.
  Reserve `print()` for user-facing CLI output.

### Subprocess calls

- Always pass `timeout=` to `subprocess.run()`.
- Always pass `check=False` and inspect `returncode` yourself — never
  use `check=True` because the error messages it produces are unhelpful.
- Capture `stderr` as well as `stdout` for diagnostics.

### Files

- Python files: **<150 lines** preferred. Files >300 lines need a
  justification in the docstring.
- Shell scripts: **<80 lines** preferred.
- Markdown docs: as long as needed — but no filler.

## Commit Conventions

This project follows [Conventional Commits](https://www.conventionalcommits.org/).

### Format

```
<type>(<scope>): <short description>

[optional body explaining why, not what]

[optional footer(s)]
```

### Types

| Type         | Use for                                                       |
| :----------- | :------------------------------------------------------------ |
| `feat`       | New user-facing feature                                       |
| `fix`        | Bug fix                                                       |
| `docs`       | Documentation-only change                                     |
| `refactor`   | Code restructuring that doesn't change behaviour              |
| `perf`       | Performance improvement                                       |
| `test`       | Test-only change                                              |
| `chore`      | Build, tooling, deps — nothing user-facing                    |
| `ci`         | CI workflow change                                            |
| `revert`     | Reverting a previous commit                                   |

### Scopes (optional but encouraged)

| Scope       | Covers                                           |
| :---------- | :----------------------------------------------- |
| `tunnel`    | `rdp_toolkit/tunnel/`                            |
| `vm`        | `rdp_toolkit/vm/`                                |
| `rdp`       | `rdp_toolkit/rdp/`                               |
| `notify`    | `rdp_toolkit/notify/`                            |
| `cli`       | `rdp_toolkit/cli.py`, `__main__.py`              |
| `config`    | `rdp_toolkit/config.py`, `configs/*.yaml`        |
| `installer` | `installers/`                                    |
| `docker`    | `docker/`                                        |
| `docs`      | `docs/`, `README.md`, `CHANGELOG.md`             |
| `workflow`  | `.github/workflows/`                             |

### Examples

```
feat(tunnel): support persistent URLs on localtunnel via --subdomain flag

Adds an optional `subdomain` field to the localtunnel provider config.
When set, the provider passes `--subdomain <name>` to `lt`, which
requests the named subdomain on loca.lt. Useful for testing where a
stable URL is required.

Closes #142.
```

```
fix(rdp): handle single-line concat bug in artifact zip parser

The connect-info.txt artifact was sometimes uploaded with all KEY: VALUE
pairs collapsed onto one line (a `echo "host: $H port: $P"` quirk in the
runner script). The parser now uses a regex that handles both multi-line
and single-line forms.

Fixes #198.
```

```
docs: expand TUNNELS.md with cloudflared bridge setup

Adds a step-by-step for `cloudflared access tcp` on the client side,
which is required when the tunnel URL is a trycloudflare.com HTTPS
endpoint (not raw TCP).
```

```
chore(installer): bump .deb version to 9.0.0

No code changes — just rebuilds the .deb against the new version
number after the v9 mega-rewrite.
```

### Anti-examples (don't do this)

```
update                                    # Too vague — what changed?
fix bug                                   # Which bug? Where?
WIP                                       # Don't commit WIPs.
feat: stuff                               # "stuff" is not a description.
```

## Pull Request Process

1. **Open the PR early** as a draft if you want feedback before it's
   ready. Mark it "Ready for review" when done.
2. **Title** should match your commit's first line (Conventional Commits
   format).
3. **Description** should explain:
   - What problem does this solve?
   - What's the user-visible change?
   - Any breaking changes?
   - Any new dependencies?
   - How did you test it?
4. **Link related issues** — use `Closes #N` / `Fixes #N` / `Ref #N` so
   GitHub auto-closes them on merge.
5. **Keep the diff small** — under ~500 lines if possible. Split big
   features into multiple PRs.
6. **Don't reformat unrelated code** — keep the diff focused on the
   actual change. If you must reformat, do it in a separate `refactor:`
   PR.
7. **Update docs** if your change affects user-visible behaviour. PRs
   that add a feature without docs will be asked to add docs before
   merge.
8. **Update CHANGELOG.md** — add an entry under `[Unreleased]` (create
   that section if it doesn't exist yet).

### Review criteria

Maintainers will look at:

- Does it pass `python3 -m py_compile` on every `.py` you touched?
- Does `python3 -m rdp_toolkit doctor` still work?
- Are the new submodules import-clean? (No `ImportError` on `from
  rdp_toolkit.X import Y`.)
- Does it match the existing code style?
- Are the commit messages Conventional-Commits-compliant?
- Is the change documented?
- Does it add a new top-level dependency? (Strong reluctance — justify
  why stdlib can't do it.)

## Testing

The toolkit currently doesn't ship a formal test suite (it relies on
import-cleanliness + manual smoke tests + the `doctor` command). If
you're adding a feature, please:

1. **Add a smoke test** as a one-liner you can paste into a shell. Add
   it to your PR description so reviewers can verify.
2. **Run `doctor`** before and after your change — it should still pass.
3. **Test on at least two platforms** if your change is cross-platform.
   The big three are Kali (Linux), Windows, and Android (Termux).

If you'd like to add a real test suite (`pytest`), please open an issue
first to discuss the scope — we don't want a test framework that requires
a live GitHub PAT to run.

## Adding Common Things

### Adding a CLI subcommand

See [ARCHITECTURE.md → "Adding a new CLI subcommand"](ARCHITECTURE.md#adding-a-new-cli-subcommand).

### Adding a tunnel provider

See [ARCHITECTURE.md → "Adding a new tunnel provider"](ARCHITECTURE.md#adding-a-new-tunnel-provider).

### Adding a notify channel

See [ARCHITECTURE.md → "Adding a new notification channel"](ARCHITECTURE.md#adding-a-new-notification-channel).

### Adding a Docker VM

1. Create `docker/<name>-rdp/Dockerfile` + `entrypoint.sh`.
2. Add the service to `docker/docker-compose.yml` (mirror the existing
   `kali-rdp` block — change ports, image name, env vars).
3. Add the short-name mapping to `rdp_toolkit/vm/compose.py:SHORT_TO_SERVICE`.
4. Add the default port to `DEFAULT_PORTS` and credentials to
   `DEFAULT_CREDENTIALS`.
5. Update `docs/ARCHITECTURE.md` and `MANIFEST.md`.
6. Test: `rdp-toolkit vm start <name>`.

## Releases

Releases are cut by maintainers. The process:

1. Update `VERSION`, `pyproject.toml` version, `__init__.py:__version__`,
   and `configs/default.yaml:version` to the new semver.
2. Add a `[X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md` (move items
   from `[Unreleased]` into it).
3. Build the artifacts: `python3 -m build`, `bash installers/debian/build.sh`,
   `installers/windows/build.bat`.
4. Tag: `git tag -s v9.0.1 -m "v9.0.1"`.
5. Push the tag: `git push upstream v9.0.1`.
6. Create a GitHub Release with the changelog section as the body, and
   attach the wheel, `.deb`, and `.exe`.

## Code of Conduct

Be excellent to each other. Disagreements happen — address them on the
merits of the code, not the person. Harassment, discrimination, or
personal attacks will not be tolerated and will result in a permanent
ban from the project.

## License

By contributing, you agree that your contributions will be licensed under
the [MIT License](../LICENSE).

## See Also

- [ARCHITECTURE.md](ARCHITECTURE.md) — Internal architecture & extension
  points.
- [SECURITY.md](SECURITY.md) — Security model — read this before
  contributing anything that touches credentials or networking.
- [MANIFEST.md](../MANIFEST.md) — File inventory (where things live).
