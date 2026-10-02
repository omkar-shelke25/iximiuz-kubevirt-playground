#!/usr/bin/env bash
#
# Catppuccin Mocha terminal setup, shared by all three rootfs targets
# (cplane, node, dev-machine). Same layout as the Rust and OpenTofu playgrounds.
#
# Runs at image build time as root. Expects the terminal tool binaries
# (starship, eza, bat, fd, zoxide, delta, atuin, lazygit, fastfetch) to be
# in /usr/local/bin already. LAB_USER must be set.
set -eu

: "${LAB_USER:?LAB_USER must be set}"

# ─── Packages ─────────────────────────────────────────────────────────────────
apt-get update
apt-get install -y --no-install-recommends \
  bash-completion \
  less \
  tmux \
  tree \
  zsh \
  zsh-autosuggestions \
  zsh-syntax-highlighting
rm -rf /var/lib/apt/lists/*

# ─── Shell completions for whatever CLIs this image has ───────────────────────
mkdir -p /etc/bash_completion.d /usr/local/share/zsh/site-functions
for cmd in kubectl helm virtctl crane docker; do
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" completion zsh > "/usr/local/share/zsh/site-functions/_${cmd}" 2>/dev/null \
      || rm -f "/usr/local/share/zsh/site-functions/_${cmd}"
  fi
done
if command -v virtctl >/dev/null 2>&1; then
  virtctl completion bash > /etc/bash_completion.d/virtctl
fi

# ─── Prompt themes: Catppuccin Mocha ──────────────────────────────────────────
# starship.toml uses Nerd Font glyphs and powerline arrows (`icons on`).
# starship-plain.toml uses colored blocks only, the default for browser tabs.
cat > /etc/starship.toml <<'TOML'
"$schema" = 'https://starship.rs/config-schema.json'

format = """
[\ue0b6](red)\
$os\
$hostname\
[\ue0b0](bg:peach fg:red)\
${env_var.PWD}\
[\ue0b0](bg:yellow fg:peach)\
$git_branch\
$git_status\
[\ue0b0](fg:yellow bg:sapphire)\
$kubernetes\
[\ue0b0](fg:sapphire bg:lavender)\
$time\
[\ue0b4 ](fg:lavender)\
$cmd_duration\
$jobs\
$line_break\
$status\
$character"""

palette = 'catppuccin_mocha'

[palettes.catppuccin_mocha]
rosewater = "#f5e0dc"
flamingo = "#f2cdcd"
pink = "#f5c2e7"
mauve = "#cba6f7"
red = "#f38ba8"
maroon = "#eba0ac"
peach = "#fab387"
yellow = "#f9e2af"
green = "#a6e3a1"
teal = "#94e2d5"
sky = "#89dceb"
sapphire = "#74c7ec"
blue = "#89b4fa"
lavender = "#b4befe"
text = "#cdd6f4"
subtext1 = "#bac2de"
subtext0 = "#a6adc8"
overlay2 = "#9399b2"
overlay1 = "#7f849c"
overlay0 = "#6c7086"
surface2 = "#585b70"
surface1 = "#45475a"
surface0 = "#313244"
base = "#1e1e2e"
mantle = "#181825"
crust = "#11111b"

[os]
disabled = false
style = "bg:red fg:crust"
format = "[$symbol ]($style)"

[os.symbols]
Ubuntu = "\uf31b"
Linux = "\U000f033d"

[hostname]
ssh_only = false
style = "bg:red fg:crust"
format = "[$hostname ]($style)"

[env_var.PWD]
variable = "PWD"
style = "bg:peach fg:crust"
format = "[ \uf07c $env_value ]($style)"

[git_branch]
symbol = "\uf418"
style = "bg:yellow"
format = "[[ $symbol $branch ](fg:crust bg:yellow)]($style)"

[git_status]
style = "bg:yellow"
format = "[[($all_status$ahead_behind )](fg:crust bg:yellow)]($style)"

[kubernetes]
disabled = false
symbol = "\U000f10fe"
style = "bg:sapphire"
format = "[[ $symbol $context( \\($namespace\\)) ](fg:crust bg:sapphire)]($style)"

[time]
disabled = false
time_format = "%H:%M"
style = "bg:lavender"
format = "[[ \uf017 $time ](fg:crust bg:lavender)]($style)"

[cmd_duration]
min_time = 2000
style = "fg:yellow"
format = "[\uf252 $duration ]($style)"

[jobs]
symbol = "\uf013 "
style = "fg:blue"

[status]
disabled = false
style = "bold fg:red"
format = "[\u2718 $status ]($style)"

[character]
success_symbol = "[\u276f](bold fg:green)"
error_symbol = "[\u276f](bold fg:red)"
TOML

cat > /etc/starship-plain.toml <<'TOML'
add_newline = true
format = "$hostname${env_var.PWD}$git_branch$git_status$kubernetes$time$cmd_duration$jobs$line_break$status$character"

[hostname]
ssh_only = false
style = "bg:#f38ba8 fg:#11111b"
format = "[ $hostname ]($style)"

[env_var.PWD]
variable = "PWD"
style = "bg:#fab387 fg:#11111b"
format = "[ $env_value ]($style)"

[git_branch]
symbol = "git:"
style = "bg:#f9e2af fg:#11111b"
format = "[ $symbol$branch ]($style)"

[git_status]
style = "bg:#f9e2af fg:#11111b"
format = "([$all_status$ahead_behind ]($style))"

[kubernetes]
disabled = false
symbol = "k8s:"
style = "bg:#74c7ec fg:#11111b"
format = "[ $symbol$context( \\($namespace\\)) ]($style)"

[time]
disabled = false
time_format = "%H:%M"
style = "bg:#b4befe fg:#11111b"
format = "[ $time ]($style)"

[cmd_duration]
min_time = 2000
style = "fg:#f9e2af"
format = " [took $duration]($style)"

[jobs]
symbol = "bg:"
style = "fg:#89b4fa"

[status]
disabled = false
style = "bold fg:#f38ba8"
format = "[$status ]($style)"

[character]
success_symbol = "[>](bold fg:#a6e3a1)"
error_symbol = "[>](bold fg:#f38ba8)"
TOML

mkdir -p /etc/fastfetch
cat > /etc/fastfetch/config.jsonc <<'JSON'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": { "source": "ubuntu_small", "padding": { "top": 1, "right": 3 } },
  "display": { "separator": "  " },
  "modules": [
    "title", "separator", "os", "kernel", "uptime", "shell",
    "cpu", "memory", "disk", "localip",
    "break",
    { "type": "command", "key": "K3s", "text": "k3s --version 2>/dev/null | head -n1 | cut -d' ' -f3 | grep . || echo client only" },
    { "type": "command", "key": "Docker", "text": "docker --version 2>/dev/null | cut -d' ' -f3 | tr -d , | grep . || echo not installed" },
    { "type": "command", "key": "KubeVirt", "text": "cat /etc/kubevirt-version 2>/dev/null || echo not set" },
    { "type": "command", "key": "KubeVirt phase", "text": "timeout 3 kubectl -n kubevirt get kubevirt kubevirt -o jsonpath={.status.phase} 2>/dev/null | grep . || echo unavailable here" },
    { "type": "command", "key": "VMs running", "text": "timeout 3 kubectl get vmi -A --no-headers 2>/dev/null | wc -l" },
    "break", "colors"
  ]
}
JSON

cat > /etc/tmux.conf <<'TMUX'
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:RGB"
set -g mouse on
set -g history-limit 50000
set -g base-index 1
setw -g pane-base-index 1
set -g status-style "bg=#313244,fg=#cdd6f4"
set -g status-left "#[bold,fg=#11111b,bg=#74c7ec] #S "
set -g status-right "#[fg=#11111b,bg=#b4befe] %H:%M "
TMUX

git config --system core.pager delta
git config --system interactive.diffFilter "delta --color-only"
git config --system delta.navigate true
git config --system delta.line-numbers true
git config --system delta.syntax-theme "Catppuccin Mocha"
git config --system merge.conflictStyle zdiff3

# ─── Shared env, sourced by bash and zsh ──────────────────────────────────────
cat > /etc/profile.d/kubevirt-shell.sh <<'PROFILE'
export BAT_THEME="Catppuccin Mocha"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# Bash fallback: plain prompt and the basics. zsh is the default shell.
[ -n "${BASH_VERSION:-}" ] || return 0
case $- in *i*) ;; *) return 0 ;; esac
[ -z "${__KUBEVIRT_BASH_INIT:-}" ] || return 0
__KUBEVIRT_BASH_INIT=1

export STARSHIP_CONFIG=/etc/starship-plain.toml
alias ls='eza --group-directories-first'
alias ll='eza -la --git --group-directories-first'
eval "$(zoxide init bash)"
eval "$(starship init bash)"
PROFILE
chmod 0644 /etc/profile.d/kubevirt-shell.sh
for rc in /root/.bashrc "/home/${LAB_USER}/.bashrc"; do
  grep -q kubevirt-shell.sh "$rc" 2>/dev/null || printf '\n. /etc/profile.d/kubevirt-shell.sh\n' >> "$rc"
done

# ─── zsh: system-wide config, per-user stubs, default shell ───────────────────
mkdir -p /etc/zsh
cat > /etc/zsh/playground.zsh <<'ZSH'
# Shared zsh config for the KubeVirt playground.
# Personal additions go in ~/.zshrc.local

emulate sh -c '. /etc/profile.d/kubevirt-shell.sh'
typeset -U path PATH
export LANG=${LANG:-C.UTF-8}
export EDITOR=${EDITOR:-vim} VISUAL=${VISUAL:-vim}

# History
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS INTERACTIVE_COMMENTS

# Keys
bindkey -e
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

# Completion (_kubectl, _helm, _virtctl and _crane live in /usr/local/share/zsh/site-functions)
autoload -Uz compinit && compinit -i
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
compdef k=kubectl

# Aliases
alias cat='bat --paging=never --style=plain'
alias grep='grep --color=auto'
alias top='btop'
alias lg='lazygit'
alias k='kubectl'

# fzf: Ctrl+T files, Alt+C directories (Ctrl+R is atuin)
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
export FZF_DEFAULT_OPTS='--height 50% --layout=reverse --border=rounded --info=inline --color=bg+:#313244,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc,marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8,selected-bg:#45475a,border:#6c7086,label:#cdd6f4'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:200 {}'"
if [[ -f ~/.fzf.zsh ]]; then
  source ~/.fzf.zsh
elif (( $+commands[fzf] )); then
  source <(fzf --zsh)
fi

# Icons need a Nerd Font on the machine that draws the terminal.
# Browser tabs cannot load one, so icons default to off. They turn on for
# Ghostty, Kitty and WezTerm over `labctl ssh`. `icons on|off` overrides
# and remembers the choice.
_icons_default() {
  if [[ -f $HOME/.config/term-icons ]]; then print -r -- "$(<$HOME/.config/term-icons)"; return; fi
  case "$TERM" in
    xterm-ghostty|xterm-kitty|wezterm) print on ;;
    *) print off ;;
  esac
}
_apply_icons() {
  local i=--icons=auto
  export STARSHIP_CONFIG=/etc/starship.toml
  if [[ $TERM_ICONS == off ]]; then
    i=--icons=never
    export STARSHIP_CONFIG=/etc/starship-plain.toml
  fi
  alias ls="eza $i --group-directories-first"
  alias ll="eza -la $i --git --group-directories-first"
  alias tree="eza --tree $i"
  export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 ${i/auto/always} --color=always {}'"
}
icons() {
  [[ $1 == on || $1 == off ]] || { print "usage: icons on|off"; return 1; }
  TERM_ICONS=$1
  mkdir -p $HOME/.config
  print -r -- $1 > $HOME/.config/term-icons
  _apply_icons
}
TERM_ICONS=$(_icons_default)
_apply_icons

# History search, smart cd, prompt
eval "$(atuin init zsh --disable-up-arrow)"
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"

# System info once per session, then the playground welcome on first login
if [[ -t 1 && -z $FASTFETCH_SHOWN ]]; then
  export FASTFETCH_SHOWN=1
  fastfetch -c /etc/fastfetch/config.jsonc
fi
if [[ -t 0 && -f $HOME/.welcome ]]; then
  command cat "$HOME/.welcome"
  echo
  rm -f "$HOME/.welcome"
fi
ZSH

cat > /etc/zsh/playground-plugins.zsh <<'ZSH'
# Loaded last: syntax highlighting must come after every other widget.
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c7086'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSH

for home in /root "/home/${LAB_USER}"; do
  # Ubuntu's /etc/zsh/zshrc runs its own compinit; skip it, ours runs once.
  printf 'skip_global_compinit=1\n' > "$home/.zshenv"
  cat > "$home/.zshrc" <<'ZSH'
# Playground defaults live in /etc/zsh. Personal additions go in ~/.zshrc.local
source /etc/zsh/playground.zsh
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
source /etc/zsh/playground-plugins.zsh
ZSH
  mkdir -p "$home/.config/atuin"
  cat > "$home/.config/atuin/config.toml" <<'TOML'
update_check = false
style = "compact"
inline_height = 20
show_preview = true
TOML
done
chown -R "${LAB_USER}:" "/home/${LAB_USER}/.zshenv" "/home/${LAB_USER}/.zshrc" "/home/${LAB_USER}/.config"

usermod -s /usr/bin/zsh root
usermod -s /usr/bin/zsh "${LAB_USER}"

# ─── Smoke test ───────────────────────────────────────────────────────────────
for tool in starship eza bat fd zoxide delta atuin lazygit fastfetch zsh; do
  "$tool" --version >/dev/null
done
zsh -ic 'exit'
rm -f /root/.zcompdump*
echo "terminal setup done"
