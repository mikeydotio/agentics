#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# greenlight — Intelligent Claude Code PreToolUse Safety Hook
#
# Three-tier decision pipeline for tool safety:
#   1. Deterministic ALLOW — known-safe readonly commands
#   2. Deterministic PASS  — known-destructive commands (with warning)
#   3. AI Fallback         — uncertain commands evaluated by Claude Sonnet
#
# Features:
#   - 150+ unconditionally safe commands, 30+ conditionally safe tools
#   - Known-destructive command database with explicit warnings
#   - Command substitution / interpolation / process substitution detection
#   - AI fallback via Anthropic API for genuinely uncertain commands
#   - Permission mode awareness (auto-disables in bypassPermissions)
#   - Configurable behavior via ~/.config/greenlight/config.yaml
#
# Default: exit 0 with no output → pass to normal permission system.
# If anything goes wrong, we fall through to this default safely.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INPUT="$(cat)"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CONFIGURATION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CONFIG_DIR="${HOME}/.config/greenlight"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DEFAULT_CONFIG="${PLUGIN_ROOT}/references/default-config.yaml"

# Auto-initialize config from bundled default on first run
if [[ ! -f "$CONFIG_FILE" && -f "$DEFAULT_CONFIG" ]]; then
  mkdir -p "$CONFIG_DIR"
  cp "$DEFAULT_CONFIG" "$CONFIG_FILE" 2>/dev/null
fi

# Defaults (used when config is missing or a key is absent)
CFG_MODE="standard"
CFG_AI_ENABLED="true"
CFG_AI_MODEL="claude-sonnet-4-6"
CFG_AI_TIMEOUT="10"
CFG_AI_SHOW_RATIONALE="true"
CFG_CUSTOM_ALLOW=""
CFG_CUSTOM_PASS=""
CFG_LOG_FILE=""
CFG_VERBOSE="false"
CFG_DISABLED_MODES="bypassPermissions"

read_config() {
  local val
  val="$(grep "^${1}:" "$CONFIG_FILE" 2>/dev/null | sed "s/^${1}:[[:space:]]*//" | tr -d "'\"")"
  printf '%s' "${val:-$2}"
}

if [[ -f "$CONFIG_FILE" ]]; then
  CFG_MODE="$(read_config mode "$CFG_MODE")"
  CFG_AI_ENABLED="$(read_config ai_enabled "$CFG_AI_ENABLED")"
  CFG_AI_MODEL="$(read_config ai_model "$CFG_AI_MODEL")"
  CFG_AI_TIMEOUT="$(read_config ai_timeout "$CFG_AI_TIMEOUT")"
  CFG_AI_SHOW_RATIONALE="$(read_config ai_show_rationale "$CFG_AI_SHOW_RATIONALE")"
  CFG_CUSTOM_ALLOW="$(read_config custom_allow "$CFG_CUSTOM_ALLOW")"
  CFG_CUSTOM_PASS="$(read_config custom_pass "$CFG_CUSTOM_PASS")"
  CFG_LOG_FILE="$(read_config log_file "$CFG_LOG_FILE")"
  CFG_VERBOSE="$(read_config verbose "$CFG_VERBOSE")"
  CFG_DISABLED_MODES="$(read_config disabled_modes "$CFG_DISABLED_MODES")"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  HELPERS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log_decision() {
  [[ -z "$CFG_LOG_FILE" ]] && return
  local ts decision detail
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  decision="$1"; detail="$2"
  printf '%s [%s] %s\n' "$ts" "$decision" "$detail" >> "$CFG_LOG_FILE" 2>/dev/null
}

allow() {
  local reason="$1"
  log_decision "ALLOW" "${TOOL_NAME}: ${reason}"
  jq -n --arg reason "$reason" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":$reason}}'
  exit 0
}

pass_with_context() {
  local reason="$1" context="$2"
  log_decision "PASS" "${TOOL_NAME}: ${reason}"
  jq -n --arg ctx "$context" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$ctx}}'
  exit 0
}

pass_silent() {
  log_decision "PASS" "${TOOL_NAME}: ${1:-deferred to user}"
  exit 0
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  PERMISSION MODE GATE
#  Skip all evaluation when running in a disabled permission mode.
#  Modes: default, plan, acceptEdits, bypassPermissions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PERM_MODE="$(printf '%s' "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null)"
if [[ -n "$PERM_MODE" && -n "$CFG_DISABLED_MODES" ]]; then
  for disabled in $CFG_DISABLED_MODES; do
    if [[ "$PERM_MODE" == "$disabled" ]]; then
      log_decision "SKIP" "disabled in ${PERM_MODE} mode"
      exit 0
    fi
  done
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  NON-BASH TOOLS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

case "$TOOL_NAME" in
  Read|Glob|Grep|WebFetch|WebSearch)
    allow "${TOOL_NAME}: readonly tool"
    ;;
  Bash)
    ;; # fall through to Bash analysis
  *)
    exit 0 ;; # pass to normal permissions
esac

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  BASH COMMAND ANALYSIS — PREPROCESSING
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -z "$COMMAND" ]] && exit 0

# ── Track whether command substitution / process substitution is present ──
HAS_CMD_SUBSTITUTION=false
HAS_PROC_SUBSTITUTION=false

# Detect $(...) and backtick command substitution
if printf '%s\n' "$COMMAND" | grep -qE '\$\(|`[^`]+`'; then
  HAS_CMD_SUBSTITUTION=true
fi

# Detect <(...) and >(...) process substitution
if printf '%s\n' "$COMMAND" | grep -qE '<\(|>\('; then
  HAS_PROC_SUBSTITUTION=true
fi

# ── Check for file-writing redirections ──
# Strip safe redirect patterns, then look for any remaining > or >>
redir_stripped="$(printf '%s\n' "$COMMAND" | sed -E '
  s/[0-9]*>&[0-9]+//g
  s/&>\/dev\/null//g
  s/[0-9]*>+\/dev\/null//g
')"
if printf '%s\n' "$redir_stripped" | grep -qE '>>?[^&]|>>$|>[[:space:]]|>$'; then
  pass_silent "file-writing redirection detected"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  COMMAND NAME EXTRACTION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

get_cmd_name() {
  local seg="$1"
  # trim leading whitespace
  seg="${seg#"${seg%%[![:space:]]*}"}"
  # strip 'env [VAR=val ...]' prefix
  if [[ "$seg" =~ ^env[[:space:]] ]]; then
    seg="${seg#env}"
    seg="${seg#"${seg%%[![:space:]]*}"}"
  fi
  # strip 'time [-p]' prefix
  if [[ "$seg" =~ ^time[[:space:]] ]]; then
    seg="${seg#time}"
    seg="${seg#"${seg%%[![:space:]]*}"}"
    if [[ "$seg" =~ ^-p[[:space:]] ]]; then
      seg="${seg#-p}"
      seg="${seg#"${seg%%[![:space:]]*}"}"
    fi
  fi
  # skip VAR=val assignments
  while [[ "$seg" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]] ]]; do
    seg="${seg#*[[:space:]]}"
    seg="${seg#"${seg%%[![:space:]]*}"}"
  done
  # first word, strip path prefix
  local cmd="${seg%%[[:space:]]*}"
  printf '%s' "${cmd##*/}"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  UNCONDITIONALLY SAFE COMMANDS
#  (pure readonly — no flags or arguments can make them destructive)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

is_always_safe() {
  case "$1" in
    # filesystem listing / info
    ls|dir|vdir|pwd|tree|file|stat|readlink|realpath|basename|dirname) return 0 ;;
    # text viewing
    cat|head|tail|less|more|tac|nl|strings|hexdump|xxd|od) return 0 ;;
    # text processing (stdin → stdout)
    sort|uniq|cut|tr|rev|paste|column|expand|unexpand|fold|fmt|wc) return 0 ;;
    awk|gawk|mawk|nawk) return 0 ;;
    # search — classic and modern
    grep|egrep|fgrep|rg|ripgrep|ag|ack|sift|ucg|pt) return 0 ;;
    # JSON / YAML / XML / data processing
    jq|yq|xq|gron|fx|dasel|dsq|q|htmlq|pup) return 0 ;;
    # CSV / tabular data (stdout only)
    mlr|miller|xsv|csvlook|csvstat|csvgrep|csvcut|csvsort|csvjoin|csvformat) return 0 ;;
    # diff / compare
    diff|cmp|comm|colordiff|delta|difft|difftastic) return 0 ;;
    # checksums
    md5sum|sha1sum|sha256sum|sha512sum|shasum|b2sum|cksum|sum) return 0 ;;
    # encoding (stdout only)
    base64|base32) return 0 ;;
    # system info
    uname|hostname|uptime|id|groups|logname|whoami|nproc|getconf|arch|lsb_release) return 0 ;;
    # hardware / device info
    lscpu|lsblk|lspci|lsusb|lsof|lsmod|lsns|lsmem) return 0 ;;
    # resource monitoring — classic
    df|du|free|vmstat|iostat|mpstat|sar|dstat) return 0 ;;
    # resource monitoring — modern TUI monitors (readonly viewers)
    htop|btop|atop|gtop|btm|bottom|glances|nmon|ctop|ytop) return 0 ;;
    # process info
    ps|pgrep|pidof|pstree) return 0 ;;
    # network info (readonly)
    ip|ifconfig|ss|netstat|route|arp|nslookup|dig|host|ping|traceroute|mtr) return 0 ;;
    # network monitoring (readonly viewers)
    bandwhich|nethogs|iftop|gping|trippy|doggo) return 0 ;;
    # shell builtins / utilities
    echo|printf|test|\[|expr|true|false|type|which|where|hash|command) return 0 ;;
    # time / date
    date|cal|timedatectl) return 0 ;;
    # environment
    env|printenv|locale) return 0 ;;
    # character encoding
    iconv|chardet|chardetect) return 0 ;;
    # log viewing
    journalctl|dmesg) return 0 ;;
    # help / docs / cheatsheets
    man|info|help|apropos|whatis|tldr|cheat|navi) return 0 ;;
    # linting / static analysis (always read-only, no --fix mode)
    shellcheck|hadolint|yamllint|jsonlint|json_pp|tflint|checkov) return 0 ;;
    # security scanners (read-only analysis)
    gitleaks|trivy|grype|syft|bandit|safety|snyk|osv-scanner|scorecard) return 0 ;;
    # code metrics / counters
    cloc|scc|loc|tokei|wc|complexity) return 0 ;;
    # modern CLI alternatives — file viewing / listing
    bat|batcat|eza|exa|lsd|broot|choose) return 0 ;;
    # modern CLI alternatives — file finding / fuzzy
    fd|fdfind|fzf|sk|peco|zoxide) return 0 ;;
    # modern CLI alternatives — system info
    procs|dust|duf|dog) return 0 ;;
    # git helpers (readonly)
    tig|onefetch|git-delta) return 0 ;;
    # terminal image / media viewers
    viu|timg|chafa|imgcat|mediainfo|ffprobe|exiv2) return 0 ;;
    # markdown / document rendering
    glow|mdcat) return 0 ;;
    # benchmarking (only measures, no side effects)
    hyperfine|bench) return 0 ;;
    # container image inspection (readonly)
    dive) return 0 ;;
    # misc harmless utilities
    seq|sleep|wait|tput|tty|mktemp|xdg-mime|xdg-open|open|pbcopy|pbpaste|xclip|xsel) return 0 ;;
    # apt-cache / dpkg-query are always readonly
    apt-cache|dpkg-query) return 0 ;;
    # archive listing (readonly)
    zipinfo) return 0 ;;
    # misc dev tools (pure stdout)
    json_verify|json_reformat|xml_pp|xmllint|tidy) return 0 ;;
    # Apple profiling / analysis / inspection (readonly)
    instruments|xctrace|xcresulttool|otool|nm) return 0 ;;
    *) return 1 ;;
  esac
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  KNOWN DESTRUCTIVE COMMANDS
#  (always potentially destructive regardless of flags)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

is_known_destructive() {
  case "$1" in
    # file removal / destruction
    rm|rmdir|unlink|shred) return 0 ;;
    # file operations that overwrite
    mv|cp) return 0 ;;
    # permissions / ownership
    chmod|chown|chgrp) return 0 ;;
    # disk / filesystem
    mkfs|fdisk|parted|wipefs|dd|mke2fs|mkswap|swapon|swapoff) return 0 ;;
    mount|umount) return 0 ;;
    # process control
    kill|killall|pkill|xkill) return 0 ;;
    # system control
    shutdown|reboot|poweroff|halt|init|systemctl) return 0 ;;
    # privilege escalation
    sudo|su|doas|pkexec) return 0 ;;
    # user / group management
    useradd|userdel|usermod|groupadd|groupdel|groupmod|passwd|chpasswd) return 0 ;;
    # network / firewall
    iptables|ip6tables|nft|ufw) return 0 ;;
    # package installation (modifies system)
    apt-get|apt|yum|dnf|pacman|zypper|brew) return 0 ;;
    snap|flatpak) return 0 ;;
    # container lifecycle (destructive actions)
    # Note: docker/podman are handled conditionally — only destructive subcommands
    # service management
    service) return 0 ;;
    # crontab editing
    crontab) return 0 ;;
    # link creation
    ln) return 0 ;;
    # truncate
    truncate) return 0 ;;
    *) return 1 ;;
  esac
}

# Return a human-readable reason for destructive commands
destructive_reason() {
  case "$1" in
    rm|rmdir|unlink|shred) echo "file deletion" ;;
    mv) echo "file move/rename (overwrites destination)" ;;
    cp) echo "file copy (overwrites destination)" ;;
    chmod|chown|chgrp) echo "permission/ownership change" ;;
    mkfs|fdisk|parted|wipefs|dd|mke2fs) echo "disk/filesystem modification" ;;
    kill|killall|pkill|xkill) echo "process termination" ;;
    shutdown|reboot|poweroff|halt) echo "system shutdown/reboot" ;;
    sudo|su|doas|pkexec) echo "privilege escalation" ;;
    apt-get|apt|yum|dnf|pacman|brew) echo "package installation/removal" ;;
    systemctl|service) echo "service management" ;;
    *) echo "potentially destructive operation" ;;
  esac
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  CONDITIONALLY SAFE COMMANDS
#  (safe only when specific flags/subcommands are absent)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── sed: safe unless -i (in-place editing) ──
is_safe_sed() {
  if printf '%s\n' "$1" | grep -qE '(^|[[:space:]])sed[[:space:]]+-[^[:space:]]*i|--in-place'; then
    return 1
  fi
  return 0
}

# ── find: safe unless -delete, -exec, -execdir, -ok, -okdir, -fls, -fprint ──
is_safe_find() {
  if printf '%s\n' "$1" | grep -qE -- '-delete|-exec\b|-execdir\b|-ok\b|-okdir\b|-fls\b|-fprint'; then
    return 1
  fi
  return 0
}

# ── tar: only listing (-t / --list) is safe ──
is_safe_tar() {
  local segment="$1"
  if printf '%s\n' "$segment" | grep -qw -- '--list'; then
    return 0
  fi
  local flags
  flags="$(printf '%s\n' "$segment" | awk '{
    for(i=1;i<=NF;i++){
      if($i=="tar"||$i~/\/tar$/){print $(i+1);exit}
    }
  }')"
  case "$flags" in
    --*)    return 1 ;;
    -*t*)   return 0 ;;
    t|t*)   return 0 ;;
    *)      return 1 ;;
  esac
}

# ── unzip: only listing (-l) and testing (-t) are safe ──
is_safe_unzip() {
  if printf '%s\n' "$1" | grep -qE '(^|[[:space:]])unzip[[:space:]]+-[^[:space:]]*[lt]'; then
    return 0
  fi
  return 1
}

# ── git: readonly subcommands only ──
is_safe_git() {
  local segment="$1"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk '{
    f=0
    for(i=1;i<=NF;i++){
      if($i=="git"||$i~/\/git$/){f=1;continue}
      if(f){
        if($i=="-C"||$i=="-c"||$i=="--git-dir"||$i=="--work-tree"||$i=="--namespace"){i++;continue}
        if($i~/^--git-dir=/||$i~/^--work-tree=/||$i~/^--namespace=/||$i~/^-c[^[:space:]]/){continue}
        if($i~/^--no-pager$/||$i~/^--bare$/||$i~/^--no-replace-objects$/||$i~/^--literal-pathspecs$/){continue}
        if($i~/^-/){continue}
        print $i;exit
      }
    }
  }')"

  case "$subcmd" in
    status|log|diff|show|shortlog|whatchanged|blame|annotate) return 0 ;;
    ls-files|ls-tree|ls-remote|cat-file) return 0 ;;
    rev-parse|rev-list|name-rev|describe|merge-base|for-each-ref) return 0 ;;
    count-objects|fsck|verify-pack|verify-commit|verify-tag) return 0 ;;
    check-ignore|check-attr|check-mailmap|check-ref-format) return 0 ;;
    var|help|version|bugreport) return 0 ;;
    cherry) return 0 ;;
    remote)
      if printf '%s\n' "$segment" | grep -qE 'remote[[:space:]]+(add|remove|rm|rename|set-url|set-head|set-branches|prune)'; then
        return 1
      fi
      return 0 ;;
    branch)
      if printf '%s\n' "$segment" | grep -qE -- '[[:space:]]-[^[:space:]]*[dDmMcC]|--delete|--move|--copy|--set-upstream|--unset-upstream|--force'; then
        return 1
      fi
      return 0 ;;
    tag)
      if printf '%s\n' "$segment" | grep -qE 'tag[[:space:]]+(-[lnL]|--list|--sort|--contains|--merged|--no-merged|--points-at)([[:space:]]|$)|tag[[:space:]]*$'; then
        return 0
      fi
      return 1 ;;
    stash)
      if printf '%s\n' "$segment" | grep -qE 'stash[[:space:]]+(list|show)'; then
        return 0
      fi
      return 1 ;;
    config)
      if printf '%s\n' "$segment" | grep -qE -- 'config[[:space:]].*(--get|--get-all|--get-regexp|--get-urlmatch|--list|-l)'; then
        return 0
      fi
      return 1 ;;
    reflog)
      if printf '%s\n' "$segment" | grep -qE 'reflog[[:space:]]+(delete|expire)'; then
        return 1
      fi
      return 0 ;;
    *) return 1 ;;
  esac
}

# ── gh: readonly subcommands only ──
is_safe_gh() {
  local segment="$1"
  local subcmd action
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="gh"){print $(i+1);exit}}}')"
  action="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="gh"){print $(i+2);exit}}}')"

  case "$subcmd" in
    pr)
      case "$action" in
        view|list|diff|checks|status) return 0 ;;
        *) return 1 ;;
      esac ;;
    issue)
      case "$action" in
        view|list|status) return 0 ;;
        *) return 1 ;;
      esac ;;
    repo)
      case "$action" in
        view|list) return 0 ;;
        *) return 1 ;;
      esac ;;
    run)
      case "$action" in
        view|list) return 0 ;;
        *) return 1 ;;
      esac ;;
    release)
      case "$action" in
        view|list) return 0 ;;
        *) return 1 ;;
      esac ;;
    workflow)
      case "$action" in
        view|list) return 0 ;;
        *) return 1 ;;
      esac ;;
    label)
      case "$action" in
        list) return 0 ;;
        *) return 1 ;;
      esac ;;
    auth)
      case "$action" in
        status) return 0 ;;
        *) return 1 ;;
      esac ;;
    api)
      if printf '%s\n' "$segment" | grep -qiE -- '-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--method[[:space:]]*(POST|PUT|DELETE|PATCH)|-F[[:space:]]|--field[[:space:]]|-f[[:space:]]|--raw-field[[:space:]]|--input[[:space:]]'; then
        return 1
      fi
      return 0 ;;
    status|help|version) return 0 ;;
    *) return 1 ;;
  esac
}

# ── docker / podman: readonly subcommands only ──
is_safe_docker() {
  local segment="$1"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="docker"||$i=="podman"){print $(i+1);exit}}}')"

  case "$subcmd" in
    ps|images|inspect|logs|stats|top|port|version|info|history|diff|events|search) return 0 ;;
    volume|network|container|image|system|context)
      local action
      action="$(printf '%s\n' "$segment" | awk -v s="$subcmd" '{for(i=1;i<=NF;i++){if($i==s){print $(i+1);exit}}}')"
      case "$action" in
        ls|list|inspect|show|logs|stats|top|port|diff|history|df) return 0 ;;
        *) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}

# ── package managers: query/info subcommands only ──
is_safe_pkg_manager() {
  local segment="$1" cmd_name="$2"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk -v c="$cmd_name" '{for(i=1;i<=NF;i++){if($i==c){print $(i+1);exit}}}')"

  case "$cmd_name" in
    npm)
      case "$subcmd" in
        list|ls|info|view|show|search|outdated|explain|why|doctor|ping|prefix|root|version|help|completion) return 0 ;;
        audit)
          if printf '%s\n' "$segment" | grep -qE 'audit[[:space:]]+fix'; then return 1; fi
          return 0 ;;
        config)
          if printf '%s\n' "$segment" | grep -qE 'config[[:space:]]+(list|get)'; then return 0; fi
          return 1 ;;
        *) return 1 ;;
      esac ;;
    yarn)
      case "$subcmd" in
        list|info|why|config|version|help|workspaces) return 0 ;;
        *) return 1 ;;
      esac ;;
    pnpm)
      case "$subcmd" in
        list|ls|why|outdated|audit|root|store|config) return 0 ;;
        *) return 1 ;;
      esac ;;
    bun)
      case "$subcmd" in
        pm) return 0 ;;
        *) return 1 ;;
      esac ;;
    pip|pip3)
      case "$subcmd" in
        list|show|freeze|check|config|debug|index|inspect) return 0 ;;
        *) return 1 ;;
      esac ;;
    cargo)
      case "$subcmd" in
        check|clippy|doc|metadata|tree|verify-project|version|help|search|info|read-manifest|pkgid) return 0 ;;
        *) return 1 ;;
      esac ;;
    go)
      case "$subcmd" in
        version|env|list|doc|vet|help) return 0 ;;
        *) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}

# ── system package queries ──
is_safe_sys_pkg() {
  local segment="$1" cmd_name="$2"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk -v c="$cmd_name" '{for(i=1;i<=NF;i++){if($i==c){print $(i+1);exit}}}')"

  case "$cmd_name" in
    dpkg)
      if printf '%s\n' "$segment" | grep -qE 'dpkg[[:space:]]+(-l|-L|-s|-S|-p|--list|--listfiles|--status|--search|--print-avail|--print-architecture|--print-foreign-architectures|--audit|--get-selections)'; then
        return 0
      fi
      return 1 ;;
    apt|apt-get)
      case "$subcmd" in
        list|show|search|depends|rdepends|policy|showpkg|showsrc|madison|changelog) return 0 ;;
        *) return 1 ;;
      esac ;;
    snap)
      case "$subcmd" in
        list|info|find|search|version|help|connections|interface|get) return 0 ;;
        *) return 1 ;;
      esac ;;
    flatpak)
      case "$subcmd" in
        list|info|search|remote-ls|remotes|history|config|document-list|permission-list) return 0 ;;
        *) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}

# ── systemctl: status/query subcommands only ──
is_safe_systemctl() {
  if printf '%s\n' "$1" | grep -qE 'systemctl[[:space:]]+(status|show|list-units|list-unit-files|is-active|is-enabled|is-failed|cat|help|list-dependencies|list-sockets|list-timers|list-jobs|list-machines)'; then
    return 0
  fi
  return 1
}

# ── tailscale: query subcommands only ──
is_safe_tailscale() {
  if printf '%s\n' "$1" | grep -qE 'tailscale[[:space:]]+(status|ip|dns|whois|version|debug|bugreport|netcheck|ping|cert)'; then
    return 0
  fi
  return 1
}

# ── interpreters / compilers: version flag only ──
is_safe_version_check() {
  local segment="$1" cmd_name="$2"
  if printf '%s\n' "$segment" | grep -qE -- '[[:space:]](--version|-V)[[:space:]]*$'; then
    return 0
  fi
  if [[ "$cmd_name" == "node" ]] && printf '%s\n' "$segment" | grep -qE -- '[[:space:]]-v[[:space:]]*$'; then
    return 0
  fi
  return 1
}

# ── curl: safe unless explicit write methods or upload flags ──
is_safe_curl() {
  local segment="$1"
  # Block if POST/PUT/DELETE/PATCH method, upload flags, or output to file
  if printf '%s\n' "$segment" | grep -qiE -- '-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]*(POST|PUT|DELETE|PATCH)|-d[[:space:]]|--data|--data-raw|--data-binary|--data-urlencode|-F[[:space:]]|--form|--upload-file|-T[[:space:]]|-o[[:space:]]|--output[[:space:]]|-O[[:space:]]|--remote-name'; then
    return 1
  fi
  return 0
}

# ── wget: safe unless downloading to file (default behavior downloads) ──
is_safe_wget() {
  local segment="$1"
  # wget -q -O - (output to stdout) or --spider (check only) are safe
  if printf '%s\n' "$segment" | grep -qE -- '--spider'; then
    return 0
  fi
  if printf '%s\n' "$segment" | grep -qE -- '-O[[:space:]]*-([[:space:]]|$)|--output-document[[:space:]]*-([[:space:]]|$)'; then
    return 0
  fi
  return 1  # default wget writes to files
}

# ── linters / formatters: safe unless --fix or --write mode ──
is_safe_linter() {
  local segment="$1"
  if printf '%s\n' "$segment" | grep -qiE -- '--fix|--write|-w[[:space:]]|--in-place|-i[[:space:]]'; then
    return 1
  fi
  return 0
}

# ── kubectl: readonly subcommands only ──
is_safe_kubectl() {
  local segment="$1"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="kubectl"){print $(i+1);exit}}}')"
  case "$subcmd" in
    get|describe|logs|top|explain|api-resources|api-versions|cluster-info|version|config) return 0 ;;
    auth)
      if printf '%s\n' "$segment" | grep -qE 'auth[[:space:]]+(can-i|whoami)'; then return 0; fi
      return 1 ;;
    *) return 1 ;;
  esac
}

# ── terraform / tofu: readonly subcommands only ──
is_safe_terraform() {
  local segment="$1" cmd_name="$2"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk -v c="$cmd_name" '{for(i=1;i<=NF;i++){if($i==c){print $(i+1);exit}}}')"
  case "$subcmd" in
    plan|show|state|output|validate|fmt|version|providers|graph|console|force-unlock) return 0 ;;
    state)
      if printf '%s\n' "$segment" | grep -qE 'state[[:space:]]+(list|show|pull)'; then return 0; fi
      return 1 ;;
    *) return 1 ;;
  esac
}

# ── make: safe for dry-run or query flags only ──
is_safe_make() {
  local segment="$1"
  if printf '%s\n' "$segment" | grep -qE -- '-n([[:space:]]|$)|--dry-run|--just-print|--recon|-q([[:space:]]|$)|--question|-p([[:space:]]|$)|--print-data-base'; then
    return 0
  fi
  return 1
}

# ── rsync: safe for dry-run only ──
is_safe_rsync() {
  if printf '%s\n' "$1" | grep -qE -- '-n([[:space:]]|$)|--dry-run'; then
    return 0
  fi
  return 1
}

# ── helm: readonly subcommands only ──
is_safe_helm() {
  local segment="$1"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="helm"){print $(i+1);exit}}}')"
  case "$subcmd" in
    list|ls|status|get|history|show|search|repo|env|version|verify|template|lint|dependency) return 0 ;;
    repo)
      if printf '%s\n' "$segment" | grep -qE 'repo[[:space:]]+(list|index)'; then return 0; fi
      return 1 ;;
    *) return 1 ;;
  esac
}

# ── aws: readonly subcommands only ──
is_safe_aws() {
  local segment="$1"
  local subcmd action
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="aws"){print $(i+1);exit}}}')"
  action="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="aws"){print $(i+2);exit}}}')"
  case "$subcmd" in
    sts) case "$action" in get-caller-identity|get-session-token|get-access-key-info) return 0 ;; *) return 1 ;; esac ;;
    configure) case "$action" in list|get) return 0 ;; *) return 1 ;; esac ;;
    *)
      # Allow describe*, list*, get*, ls actions across all services
      case "$action" in
        describe*|list*|get*|show*|ls|ls-*|head*) return 0 ;;
        *) return 1 ;;
      esac ;;
  esac
}

# ── gcloud: readonly subcommands only ──
is_safe_gcloud() {
  local segment="$1"
  local subcmd action
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="gcloud"){print $(i+1);exit}}}')"
  action="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="gcloud"){print $(i+2);exit}}}')"
  case "$subcmd" in
    config) case "$action" in list|get-value|configurations) return 0 ;; *) return 1 ;; esac ;;
    auth) case "$action" in list|print-access-token|print-identity-token) return 0 ;; *) return 1 ;; esac ;;
    info|version|help|topic) return 0 ;;
    *)
      # Allow describe, list across all services
      case "$action" in
        describe|list|get-iam-policy|ls) return 0 ;;
        *) return 1 ;;
      esac ;;
  esac
}

# ── version managers: query subcommands only ──
is_safe_version_manager() {
  local segment="$1" cmd_name="$2"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk -v c="$cmd_name" '{for(i=1;i<=NF;i++){if($i==c){print $(i+1);exit}}}')"
  case "$cmd_name" in
    nvm)
      case "$subcmd" in
        ls|list|current|version|which|alias|ls-remote|version-remote) return 0 ;;
        *) return 1 ;;
      esac ;;
    fnm)
      case "$subcmd" in
        ls|list|current|default|ls-remote|completions|env) return 0 ;;
        *) return 1 ;;
      esac ;;
    pyenv)
      case "$subcmd" in
        version|versions|which|whence|root|prefix|commands|completions|help|shims) return 0 ;;
        *) return 1 ;;
      esac ;;
    rbenv)
      case "$subcmd" in
        version|versions|which|whence|root|prefix|commands|completions|help|shims) return 0 ;;
        *) return 1 ;;
      esac ;;
    volta)
      case "$subcmd" in
        list|which|help|completions) return 0 ;;
        *) return 1 ;;
      esac ;;
    mise|rtx)
      case "$subcmd" in
        ls|list|current|which|where|doctor|version|env|settings|alias|plugins|completion) return 0 ;;
        *) return 1 ;;
      esac ;;
    asdf)
      case "$subcmd" in
        list|current|where|which|info|help|plugin) return 0 ;;
        *) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}

# ── vercel: dev/query safe, deploy/publish unsafe ──
is_safe_vercel() {
  local segment="$1"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="vercel"){print $(i+1);exit}}}')"
  case "$subcmd" in
    dev|build|ls|list|inspect|logs|whoami|project|teams|link|pull|help|--version|-V) return 0 ;;
    env)
      if printf '%s\n' "$segment" | grep -qE 'env[[:space:]]+(ls|list|pull)'; then return 0; fi
      return 1 ;;
    *) return 1 ;;
  esac
}

# ── netlify: dev/query safe, deploy unsafe ──
is_safe_netlify() {
  local segment="$1"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="netlify"){print $(i+1);exit}}}')"
  case "$subcmd" in
    dev|build|status|open|login|link|unlink|env|logs|recipes|help|--version|-V) return 0 ;;
    sites)
      if printf '%s\n' "$segment" | grep -qE 'sites[[:space:]]+(list|show)'; then return 0; fi
      return 1 ;;
    *) return 1 ;;
  esac
}

# ── wrangler (Cloudflare): dev/query safe, deploy unsafe ──
is_safe_wrangler() {
  local segment="$1"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="wrangler"){print $(i+1);exit}}}')"
  case "$subcmd" in
    dev|build|init|generate|types|whoami|login|docs|help|--version|-V) return 0 ;;
    *) return 1 ;;
  esac
}

# ── xcodebuild: build/test/analyze safe, exportArchive unsafe ──
is_safe_xcodebuild() {
  local segment="$1"
  # exportArchive produces distributable artifacts (IPAs, etc.)
  if printf '%s\n' "$segment" | grep -qE -- '-exportArchive'; then
    return 1
  fi
  # All other operations (build, test, analyze, clean, archive, query) write to default build products
  return 0
}

# ── swift: SPM build/test/run + version safe ──
is_safe_swift() {
  local segment="$1"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="swift"){print $(i+1);exit}}}')"
  case "$subcmd" in
    # SPM operations (write to .build/ — default build products)
    build|test|run|package) return 0 ;;
    # version/help/REPL
    --version|-version|-V|help|repl) return 0 ;;
    *) return 1 ;;
  esac
}

# ── xcrun: build tools and simulator management safe ──
is_safe_xcrun() {
  local segment="$1"
  local tool
  tool="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="xcrun"){print $(i+1);exit}}}')"
  case "$tool" in
    # SDK / tool path queries
    --sdk|--find|--show-sdk-path|--show-sdk-platform-path|--show-sdk-version|--version) return 0 ;;
    # Simulator management (local-only state)
    simctl) return 0 ;;
    # Build tools (output to default build products)
    swift|swiftc|clang|clang++|ld|libtool|lipo|otool|nm|size|strings|dsymutil|dwarfdump|bitcode_strip) return 0 ;;
    # Asset compilation tools
    actool|ibtool|momc|mapc|xcresulttool|stapler) return 0 ;;
    # Delegate to xcodebuild checker
    xcodebuild) is_safe_xcodebuild "$segment" && return 0; return 1 ;;
    *) return 1 ;;
  esac
}

# ── CocoaPods: install/update/query safe, trunk publish unsafe ──
is_safe_pod() {
  local segment="$1"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="pod"){print $(i+1);exit}}}')"
  case "$subcmd" in
    # Dependency resolution (writes to Pods/ and Podfile.lock — standard)
    install|update|deintegrate|init) return 0 ;;
    # Query commands
    list|search|try|spec|env|outdated|cache|repo|version|help|--version) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Carthage: build/update safe ──
is_safe_carthage() {
  local segment="$1"
  local subcmd
  subcmd="$(printf '%s\n' "$segment" | awk '{for(i=1;i<=NF;i++){if($i=="carthage"){print $(i+1);exit}}}')"
  case "$subcmd" in
    # Build/dependency resolution (writes to Carthage/ — default location)
    build|bootstrap|update|checkout) return 0 ;;
    # Query
    version|help|outdated|--version) return 0 ;;
    *) return 1 ;;
  esac
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  SEGMENT SAFETY CHECK
#  Returns: 0 = safe, 1 = uncertain, 2 = known destructive
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DESTRUCTIVE_CMD=""  # tracks which command triggered destructive flag

is_safe_segment() {
  local segment="$1"
  local cmd_name
  cmd_name="$(get_cmd_name "$segment")"

  # empty segment (e.g. trailing ;)
  [[ -z "$cmd_name" ]] && return 0

  # check custom allow list from config
  if [[ -n "$CFG_CUSTOM_ALLOW" ]]; then
    for allowed in $CFG_CUSTOM_ALLOW; do
      [[ "$cmd_name" == "$allowed" ]] && return 0
    done
  fi

  # check custom pass list from config
  if [[ -n "$CFG_CUSTOM_PASS" ]]; then
    for blocked in $CFG_CUSTOM_PASS; do
      if [[ "$cmd_name" == "$blocked" ]]; then
        DESTRUCTIVE_CMD="$cmd_name"
        return 2
      fi
    done
  fi

  # known destructive — but check for conditionally-safe overrides first
  # Some "destructive" commands have readonly subcommands (systemctl status, etc.)
  case "$cmd_name" in
    systemctl)  is_safe_systemctl "$segment" && return 0
                DESTRUCTIVE_CMD="$cmd_name"; return 2 ;;
    docker|podman)
                is_safe_docker "$segment" && return 0
                DESTRUCTIVE_CMD="$cmd_name"; return 2 ;;
    apt|apt-get)
                is_safe_sys_pkg "$segment" "$cmd_name" && return 0
                DESTRUCTIVE_CMD="$cmd_name"; return 2 ;;
    dpkg)       is_safe_sys_pkg "$segment" "$cmd_name" && return 0
                DESTRUCTIVE_CMD="$cmd_name"; return 2 ;;
    snap|flatpak)
                is_safe_sys_pkg "$segment" "$cmd_name" && return 0
                DESTRUCTIVE_CMD="$cmd_name"; return 2 ;;
  esac

  if is_known_destructive "$cmd_name"; then
    DESTRUCTIVE_CMD="$cmd_name"
    return 2
  fi

  # unconditionally safe
  if is_always_safe "$cmd_name"; then
    return 0
  fi

  # conditionally safe — dispatch by command
  case "$cmd_name" in
    sed)                              is_safe_sed "$segment" && return 0 ;;
    find)                             is_safe_find "$segment" && return 0 ;;
    tar)                              is_safe_tar "$segment" && return 0 ;;
    unzip)                            is_safe_unzip "$segment" && return 0 ;;
    git)                              is_safe_git "$segment" && return 0 ;;
    gh)                               is_safe_gh "$segment" && return 0 ;;
    npm|yarn|pnpm|bun|pip|pip3|cargo|go)
                                      is_safe_pkg_manager "$segment" "$cmd_name" && return 0 ;;
    tailscale)                        is_safe_tailscale "$segment" && return 0 ;;
    # HTTP clients — safe for GET, unsafe for POST/PUT/DELETE
    curl|curlie)                      is_safe_curl "$segment" && return 0 ;;
    wget)                             is_safe_wget "$segment" && return 0 ;;
    # linters / formatters — safe unless --fix or --write
    eslint|prettier|biome|stylelint|rubocop|autopep8|black|isort|ruff|gofmt|goimports|rustfmt|clang-format|shfmt|taplo|dprint|swiftlint|swiftformat)
                                      is_safe_linter "$segment" && return 0 ;;
    # type checkers / compilers (readonly analysis modes)
    tsc|mypy|pyright|flow|typecheck)  is_safe_linter "$segment" && return 0 ;;
    # container orchestration — readonly subcommands
    kubectl|oc)                       is_safe_kubectl "$segment" && return 0 ;;
    helm)                             is_safe_helm "$segment" && return 0 ;;
    # infrastructure — readonly subcommands
    terraform|tofu)                   is_safe_terraform "$segment" "$cmd_name" && return 0 ;;
    # cloud CLIs — readonly subcommands
    aws)                              is_safe_aws "$segment" && return 0 ;;
    gcloud)                           is_safe_gcloud "$segment" && return 0 ;;
    # build tools — safe for dry-run / query only
    make|gmake)                       is_safe_make "$segment" && return 0 ;;
    cmake)                            is_safe_version_check "$segment" "$cmd_name" && return 0 ;;
    # sync — safe for dry-run only
    rsync)                            is_safe_rsync "$segment" && return 0 ;;
    # version managers — query subcommands only
    nvm|fnm|pyenv|rbenv|volta|mise|rtx|asdf)
                                      is_safe_version_manager "$segment" "$cmd_name" && return 0 ;;
    # package runners — execute arbitrary code, always uncertain
    npx|bunx|pipx|uvx)               return 1 ;;
    # interpreters / compilers — version flag only
    node|python|python3|ruby|perl|php|java|javac|rustc|gcc|g++|clang|clang++|cc|kotlin|scala)
                                      is_safe_version_check "$segment" "$cmd_name" && return 0 ;;
    # test runners — generally safe (they run tests, don't modify code)
    jest|vitest|mocha|pytest|rspec|phpunit|junit|ava|tap|nyc|c8|xctest)
                                      return 0 ;;
    # pandoc — safe for rendering, but -o flag writes files
    pandoc)                           [[ "$segment" != *" -o "* && "$segment" != *" --output"* ]] && return 0 ;;
    # ── web build tools (output to default build dirs — dist/, .next/, etc.) ──
    vite|next|nuxt|nuxi|astro|webpack|rollup|esbuild|parcel|turbo|tsup|remix|svelte-kit)
                                      return 0 ;;
    # web deployment CLIs — dev/query safe, deploy/publish unsafe
    vercel)                           is_safe_vercel "$segment" && return 0 ;;
    netlify)                          is_safe_netlify "$segment" && return 0 ;;
    wrangler)                         is_safe_wrangler "$segment" && return 0 ;;
    # ── Apple / iOS / macOS development ──
    xcodebuild)                       is_safe_xcodebuild "$segment" && return 0 ;;
    swift)                            is_safe_swift "$segment" && return 0 ;;
    xcrun)                            is_safe_xcrun "$segment" && return 0 ;;
    # compilers / generators / build tools (output to default build products)
    swiftc|xcodegen|lipo)             return 0 ;;
    # dependency managers
    pod)                              is_safe_pod "$segment" && return 0 ;;
    carthage)                         is_safe_carthage "$segment" && return 0 ;;
    # automation — uncertain by default (lanes can deploy)
    fastlane)                         return 1 ;;
  esac

  return 1  # uncertain
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  AI FALLBACK — Query Claude Sonnet via Anthropic API
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ai_check() {
  local cmd="$1"
  local api_key="${ANTHROPIC_API_KEY:-}"

  if [[ -z "$api_key" ]]; then
    log_decision "AI_SKIP" "ANTHROPIC_API_KEY not set"
    return 1  # signal caller to fall through to pass
  fi

  # Build the prompt — escaped for JSON embedding via jq
  local user_prompt
  user_prompt="$(cat <<'PROMPT_END'
Is this command, as written, potentially destructive?

Consider all of the following:
- Does it modify, delete, move, or overwrite any files or directories?
- Does it change system state (processes, services, permissions, network, cron)?
- Does it push, publish, deploy, or send data to external services?
- Does it write to non-stdout destinations (files, sockets, APIs)?
- Could variable expansions, globs, or command substitutions result in unintended destructive targets?
- Does it install, remove, or modify software packages?
- Does it change git history, branches, or tags in a non-readonly way?

answer=true means the command IS potentially destructive or has side effects beyond stdout.
answer=false means the command is demonstrably safe and read-only.
PROMPT_END
  )"

  local full_prompt
  full_prompt="$(printf '%s\n\nCommand:\n```\n%s\n```' "$user_prompt" "$cmd")"

  # Make the API call with structured output
  local response
  response="$(curl -s --max-time "$CFG_AI_TIMEOUT" \
    https://api.anthropic.com/v1/messages \
    -H "x-api-key: ${api_key}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(jq -n \
      --arg model "$CFG_AI_MODEL" \
      --arg prompt "$full_prompt" \
      '{
        model: $model,
        max_tokens: 512,
        messages: [{role: "user", content: $prompt}],
        output_config: {
          format: {
            type: "json_schema",
            schema: {
              type: "object",
              properties: {
                answer: {type: "boolean", description: "true if potentially destructive, false if safe"},
                rationale: {type: "string", description: "explanation of the safety assessment"}
              },
              required: ["answer", "rationale"],
              additionalProperties: false
            }
          }
        }
      }')" 2>/dev/null)" || {
    log_decision "AI_FAIL" "curl failed"
    return 1
  }

  # Parse the response
  local ai_text
  ai_text="$(printf '%s' "$response" | jq -r '.content[0].text // empty' 2>/dev/null)"

  if [[ -z "$ai_text" ]]; then
    # Check for API error
    local api_error
    api_error="$(printf '%s' "$response" | jq -r '.error.message // empty' 2>/dev/null)"
    if [[ -n "$api_error" ]]; then
      log_decision "AI_ERROR" "$api_error"
    else
      log_decision "AI_FAIL" "empty response"
    fi
    return 1
  fi

  local answer rationale
  answer="$(printf '%s' "$ai_text" | jq -r '.answer // empty' 2>/dev/null)"
  rationale="$(printf '%s' "$ai_text" | jq -r '.rationale // empty' 2>/dev/null)"

  if [[ -z "$answer" || -z "$rationale" ]]; then
    log_decision "AI_FAIL" "could not parse response"
    return 1
  fi

  log_decision "AI_RESULT" "answer=${answer} rationale=${rationale}"

  # Build context message for the user
  local context_msg
  if [[ "$answer" == "true" ]]; then
    context_msg="[greenlight] AI safety analysis: POTENTIALLY DESTRUCTIVE. ${rationale}"
    pass_with_context "AI determined command is potentially destructive" "$context_msg"
  else
    # AI says safe — allow, but still surface rationale if configured
    if [[ "$CFG_AI_SHOW_RATIONALE" == "true" ]]; then
      log_decision "ALLOW" "AI confirmed safe: ${rationale}"
      jq -n --arg rationale "[greenlight] AI analysis: ${rationale}" \
        '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"AI confirmed safe","additionalContext":$rationale}}'
      exit 0
    else
      allow "AI confirmed safe"
    fi
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  QUOTE-AWARE HELPERS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Split a command on ||, &&, |, ; while respecting single/double quotes.
# Outputs one segment per line.
split_segments() {
  printf '%s\n' "$1" | awk '
  BEGIN { seg = ""; in_sq = 0; in_dq = 0 }
  {
    n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)

      # inside single quotes — everything literal until closing quote
      if (in_sq) {
        seg = seg c
        if (c == "\047") in_sq = 0
        continue
      }

      # inside double quotes — handle backslash escapes
      if (in_dq) {
        if (c == "\\" && i < n) { seg = seg c substr($0, i+1, 1); i++; continue }
        seg = seg c
        if (c == "\"") in_dq = 0
        continue
      }

      # outside all quotes
      if (c == "\\" && i < n) { seg = seg c substr($0, i+1, 1); i++; continue }
      if (c == "\047") { in_sq = 1; seg = seg c; continue }
      if (c == "\"")   { in_dq = 1; seg = seg c; continue }

      # shell operators — split here
      if (c == "|" && i < n && substr($0, i+1, 1) == "|") { print seg; seg = ""; i++; continue }
      if (c == "&" && i < n && substr($0, i+1, 1) == "&") { print seg; seg = ""; i++; continue }
      if (c == "|") { print seg; seg = ""; continue }
      if (c == ";") { print seg; seg = ""; continue }

      seg = seg c
    }
  }
  END { if (seg != "") print seg }
  '
}

# Extract the inner commands from $(...) and backtick substitutions.
# Handles nested $() via paren-depth counting. Skips single-quoted regions.
# Outputs one extracted command per line.
extract_cmd_subs() {
  printf '%s\n' "$1" | awk '
  {
    s = $0; n = length(s); in_sq = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)

      # single-quoted region — $() is literal inside
      if (c == "\047") { in_sq = !in_sq; continue }
      if (in_sq) continue

      # $(...) — balanced paren extraction
      if (c == "$" && i < n && substr(s, i+1, 1) == "(") {
        i += 2; depth = 1; cmd = ""
        while (i <= n && depth > 0) {
          ch = substr(s, i, 1)
          if (ch == "(") depth++
          else if (ch == ")") { depth--; if (depth == 0) break }
          cmd = cmd ch; i++
        }
        if (cmd != "") print cmd
        continue
      }

      # backtick substitution
      if (c == "`") {
        i++; cmd = ""
        while (i <= n && substr(s, i, 1) != "`") {
          cmd = cmd substr(s, i, 1); i++
        }
        if (cmd != "") print cmd
        continue
      }
    }
  }
  '
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  MAIN: split command into segments & check each one
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

all_safe=true
any_destructive=false
any_uncertain=false
destructive_detail=""

# Split on shell operators: ||, &&, |, ;
# Quote-aware — operators inside single/double quotes are not split points.
while IFS= read -r segment; do
  segment="${segment#"${segment%%[![:space:]]*}"}"   # trim leading
  segment="${segment%"${segment##*[![:space:]]}"}"   # trim trailing
  [[ -z "$segment" ]] && continue

  is_safe_segment "$segment"
  result=$?

  case $result in
    0) ;; # safe, continue checking
    1) all_safe=false; any_uncertain=true ;;
    2) all_safe=false; any_destructive=true
       destructive_detail="$(destructive_reason "$DESTRUCTIVE_CMD"): \`${DESTRUCTIVE_CMD}\`" ;;
  esac
done < <(split_segments "$COMMAND")

# ── Check command substitutions for safety ──
# Instead of blanket-rejecting $() / backticks, extract each inner command
# and run it through the same safety checks.
if $all_safe && $HAS_CMD_SUBSTITUTION; then
  while IFS= read -r inner_cmd; do
    [[ -z "$inner_cmd" ]] && continue
    # Inner commands may contain pipes — split and check each sub-segment
    while IFS= read -r inner_seg; do
      inner_seg="${inner_seg#"${inner_seg%%[![:space:]]*}"}"
      inner_seg="${inner_seg%"${inner_seg##*[![:space:]]}"}"
      [[ -z "$inner_seg" ]] && continue
      is_safe_segment "$inner_seg"
      if [[ $? -ne 0 ]]; then
        all_safe=false
        any_uncertain=true
        break 2
      fi
    done < <(split_segments "$inner_cmd")
  done < <(extract_cmd_subs "$COMMAND")
fi

# Process substitution <(...) / >(...) remains blanket-uncertain (rare, hard to analyze)
if $all_safe && $HAS_PROC_SUBSTITUTION; then
  all_safe=false
  any_uncertain=true
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DECISION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if $all_safe; then
  allow "Bash: safe readonly command(s)"
fi

if $any_destructive; then
  pass_with_context "known destructive command" \
    "[greenlight] Detected ${destructive_detail} — requesting user confirmation."
fi

# Uncertain commands — behavior depends on mode and AI config
if $any_uncertain; then
  case "$CFG_MODE" in
    strict)
      pass_silent "strict mode: uncertain command deferred to user"
      ;;
    standard|permissive)
      if [[ "$CFG_AI_ENABLED" == "true" ]]; then
        ai_check "$COMMAND"
        # If ai_check returns (didn't exit), it means AI call failed
        # Fall through to pass
        log_decision "PASS" "AI fallback failed, deferring to user"
      fi
      ;;
  esac
fi

# Default: pass to normal permission system
exit 0
