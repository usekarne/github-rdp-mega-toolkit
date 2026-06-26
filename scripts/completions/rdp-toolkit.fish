# =============================================================================
# rdp-toolkit.fish — Fish shell completion for the RDP Mega Toolkit v9 CLI.
#
# Install:
#   cp scripts/completions/rdp-toolkit.fish ~/.config/fish/completions/rdp-toolkit.fish
#   # (or system-wide:)
#   sudo cp scripts/completions/rdp-toolkit.fish /usr/share/fish/completions/rdp-toolkit.fish
#
# Fish reloads completions automatically — no `source` needed.
#
# Mirror of scripts/completions/rdp-toolkit.bash + .zsh. Update all three
# together when adding a subcommand or a flag.
# =============================================================================

# Disable file completion for the top-level command — it only takes subcommands.
complete -c rdp-toolkit -f
complete -c rdp_toolkit -f

# Global flags.
complete -c rdp-toolkit -s h -l help -d 'show help'
complete -c rdp-toolkit -s V -l version -d 'show version'
complete -c rdp_toolkit -s h -l help -d 'show help'
complete -c rdp_toolkit -s V -l version -d 'show version'

# --- Subcommands ------------------------------------------------------------
complete -c rdp-toolkit -n '__fish_use_subcommand' -a install   -d 'install platform dependencies'
complete -c rdp-toolkit -n '__fish_use_subcommand' -a start     -d 'start an RDP session'
complete -c rdp-toolkit -n '__fish_use_subcommand' -a stop      -d 'stop active RDP session(s)'
complete -c rdp-toolkit -n '__fish_use_subcommand' -a status    -d 'show active runs'
complete -c rdp-toolkit -n '__fish_use_subcommand' -a connect   -d 'print ready-to-paste xfreerdp command'
complete -c rdp-toolkit -n '__fish_use_subcommand' -a config    -d 'auto-generate YAML config'
complete -c rdp-toolkit -n '__fish_use_subcommand' -a tunnel    -d 'manage tunnels'
complete -c rdp-toolkit -n '__fish_use_subcommand' -a vm        -d 'manage Docker VMs'
complete -c rdp-toolkit -n '__fish_use_subcommand' -a rotate    -d 'rotate password for a run'
complete -c rdp-toolkit -n '__fish_use_subcommand' -a kill      -d 'cancel runs'
complete -c rdp-toolkit -n '__fish_use_subcommand' -a doctor    -d 'diagnose installation'

# --- install ----------------------------------------------------------------
complete -c rdp-toolkit -n '__fish_seen_subcommand_from install' -l platform \
    -d 'target platform (default: auto-detect)' -x -a 'kali\t"Kali Linux"
                                                    windows\t"Windows"
                                                    android\t"Android (Termux)"
                                                    ubuntu\t"Ubuntu / Debian"'

# --- start ------------------------------------------------------------------
complete -c rdp-toolkit -n '__fish_seen_subcommand_from start' -l hours \
    -d 'session duration in hours' -x -a '1 2 4 6'
complete -c rdp-toolkit -n '__fish_seen_subcommand_from start' -l profile \
    -d 'optimization profile' -x -a 'productivity\t"Balanced for daily work"
                                       gaming\t"Low-latency for games"
                                       minimal\t"Lightweight for slow links"'

# --- stop / status / doctor -------------------------------------------------
# (no flags other than -h --help)

# --- connect ----------------------------------------------------------------
complete -c rdp-toolkit -n '__fish_seen_subcommand_from connect' -a '(__rdp_toolkit_run_ids)'

# --- config -----------------------------------------------------------------
complete -c rdp-toolkit -n '__fish_seen_subcommand_from config' -l platform \
    -d 'target platform' -x -a 'kali windows android ubuntu'

# --- tunnel -----------------------------------------------------------------
complete -c rdp-toolkit -n '__fish_seen_subcommand_from tunnel' -a 'list status test'
complete -c rdp-toolkit -n '__fish_seen_subcommand_from tunnel; and __fish_seen_subcommand_from test' \
    -a 'serveo localhost.run cloudflare localtunnel all'

# --- vm ---------------------------------------------------------------------
complete -c rdp-toolkit -n '__fish_seen_subcommand_from vm' -a 'start stop shell'
complete -c rdp-toolkit -n '__fish_seen_subcommand_from vm; and __fish_seen_subcommand_from start stop shell' \
    -a 'kali ubuntu windows'

# --- rotate -----------------------------------------------------------------
complete -c rdp-toolkit -n '__fish_seen_subcommand_from rotate' -a '(__rdp_toolkit_run_ids)'

# --- kill -------------------------------------------------------------------
complete -c rdp-toolkit -n '__fish_seen_subcommand_from kill' -a 'all (__rdp_toolkit_run_ids)'

# --- Helper: list recent run-ids --------------------------------------------
# Calls `rdp-toolkit status` and parses the first column. Cached for 30s via
# a global variable to avoid hitting the GitHub API on every keystroke.
function __rdp_toolkit_run_ids
    if not set -q __rdp_toolkit_run_ids_cache
        or test (date +%s) -lt (math $__rdp_toolkit_run_ids_cache_time + 30 2>/dev/null; or echo 0)
        set -g __rdp_toolkit_run_ids_cache (rdp-toolkit status 2>/dev/null | awk '/^  - / {print $2}' | head -20)
        set -g __rdp_toolkit_run_ids_cache_time (date +%s)
    end
    echo $__rdp_toolkit_run_ids_cache
end
