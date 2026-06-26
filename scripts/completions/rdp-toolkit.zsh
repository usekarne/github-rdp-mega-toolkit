#compdef rdp-toolkit rdp_toolkit
# =============================================================================
# rdp-toolkit.zsh — Zsh completion for the RDP Mega Toolkit v9 CLI.
#
# Install:
#   sudo cp scripts/completions/rdp-toolkit.zsh /usr/local/share/zsh/site-functions/_rdp-toolkit
#   # or, per-user (recommended):
#   mkdir -p ~/.zsh/completions
#   cp scripts/completions/rdp-toolkit.zsh ~/.zsh/completions/_rdp-toolkit
#   echo 'fpath=(~/.zsh/completions $fpath); autoload -Uz compinit; compinit' >> ~/.zshrc
#   source ~/.zshrc
#
# Mirror of scripts/completions/rdp-toolkit.bash. Update both together when
# adding a subcommand or a flag.
# =============================================================================

local -a subcommands
subcommands=(
    'install:install platform dependencies'
    'start:start an RDP session'
    'stop:stop active RDP session(s)'
    'status:show active runs'
    'connect:print ready-to-paste xfreerdp command'
    'config:auto-generate YAML config'
    'tunnel:manage tunnels'
    'vm:manage Docker VMs'
    'rotate:rotate password for a run'
    'kill:cancel runs'
    'doctor:diagnose installation'
)

local -a platforms
platforms=('kali' 'windows' 'android' 'ubuntu')

local -a profiles
profiles=('productivity' 'gaming' 'minimal')

local -a tunnel_actions
tunnel_actions=('list' 'status' 'test')

local -a tunnel_providers
tunnel_providers=('serveo' 'localhost.run' 'cloudflare' 'localtunnel' 'all')

local -a vm_actions
vm_actions=('start' 'stop' 'shell')

local -a vm_names
vm_names=('kali' 'ubuntu' 'windows')

_rdp-toolkit() {
    local context state line curcontext="$curcontext"
    typeset -A opt_args

    _arguments -C \
        '(-h --help)'{-h,--help}'[show help]' \
        '(-V --version)'{-V,--version}'[show version]' \
        '1: :->subcmd' \
        '*::arg:->args'

    case $state in
        subcmd)
            _describe 'command' subcommands
            ;;
        args)
            case ${line[1]} in
                install)
                    _arguments \
                        '--platform[target platform]:platform:->platforms' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                start)
                    _arguments \
                        '--hours[session duration in hours]:hours:(1 2 4 6)' \
                        '--profile[optimization profile]:profile:->profiles' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                stop)
                    _arguments '(-h --help)'{-h,--help}'[show help]'
                    ;;
                status)
                    _arguments '(-h --help)'{-h,--help}'[show help]'
                    ;;
                connect)
                    _arguments ':run_id: '
                    ;;
                config)
                    _arguments \
                        '--platform[target platform]:platform:->platforms' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                tunnel)
                    _arguments \
                        '1:action:->tunnel_actions' \
                        '2:provider:->tunnel_providers'
                    ;;
                vm)
                    _arguments \
                        '1:action:->vm_actions' \
                        '2:name:->vm_names'
                    ;;
                rotate)
                    _arguments ':run_id: '
                    ;;
                kill)
                    _arguments ':target:(all)'
                    ;;
                doctor)
                    _arguments '(-h --help)'{-h,--help}'[show help]'
                    ;;
            esac

            case $state in
                platforms)  _describe 'platform' platforms ;;
                profiles)   _describe 'profile' profiles ;;
                tunnel_actions)   _describe 'tunnel action' tunnel_actions ;;
                tunnel_providers) _describe 'tunnel provider' tunnel_providers ;;
                vm_actions) _describe 'vm action' vm_actions ;;
                vm_names)   _describe 'vm name' vm_names ;;
            esac
            ;;
    esac
}

_rdp-toolkit "$@"
