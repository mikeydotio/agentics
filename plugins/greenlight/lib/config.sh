#!/usr/bin/env bash
# Shared flat configuration reader. Values are data, never shell code.

# Ordered schema and destination names; shipped values live only in the bundle.
GL_KEYS=(mode ai_enabled ai_model ai_timeout ai_show_rationale custom_allow custom_pass log_file verbose disabled_modes plan_explorer_enabled plan_explorer_scratch_prefix plan_explorer_worktree_segment plan_explorer_uncertain plan_explorer_model)
GL_VARS=(CFG_MODE CFG_AI_ENABLED CFG_AI_MODEL CFG_AI_TIMEOUT CFG_AI_SHOW_RATIONALE CFG_CUSTOM_ALLOW CFG_CUSTOM_PASS CFG_LOG_FILE CFG_VERBOSE CFG_DISABLED_MODES CFG_PLAN_EXPLORER_ENABLED CFG_PLAN_EXPLORER_SCRATCH_PREFIX CFG_PLAN_EXPLORER_WORKTREE_SEGMENT CFG_PLAN_EXPLORER_UNCERTAIN CFG_PLAN_EXPLORER_MODEL)

# Report a configuration failure to stderr, retaining context for every caller.
gl_config_error() {
  printf 'greenlight config: %s\n' "$*" >&2
  return 1
}

# Resolve a recognized key into GL_INDEX; arbitrary names never become variables.
gl_config_index() {
  local n
  for n in "${!GL_KEYS[@]}"; do
    if [[ "${GL_KEYS[n]}" == "$1" ]]; then GL_INDEX="$n"; return 0; fi
  done
  return 1
}

# Store outer-whitespace-trimmed text in GL_TEXT without spawning a process.
gl_config_trim() {
  GL_TEXT="$1"
  GL_TEXT="${GL_TEXT#"${GL_TEXT%%[!$' \t\r']*}"}"
  GL_TEXT="${GL_TEXT%"${GL_TEXT##*[!$' \t\r']}"}"
}

# Identify settings whose explicit empty value is meaningful.
gl_config_empty_allowed() {
  case "$1" in disabled_modes|custom_allow|custom_pass|log_file) return 0 ;; esac
  return 1
}

# Validate recognized scalar values without changing permission-policy vocabulary.
gl_config_valid_value() {
  local key="$1" value="$2"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1
  [[ -n "$value" ]] || return 0  # empty scalars inherit the bundled value
  case "$key" in
    ai_enabled|ai_show_rationale|verbose|plan_explorer_enabled)
      [[ "$value" == true || "$value" == false ]] ;;
    mode) [[ "$value" == standard || "$value" == strict || "$value" == permissive ]] ;;
    ai_timeout) [[ "$value" =~ ^[1-9][0-9]*$ ]] ;;
    *) return 0 ;;
  esac
}

# Parse one flat line into GL_INDEX/GL_VALUE; return 2 for unrelated content.
gl_config_parse_line() {
  local line="$1" key rest quote
  gl_config_trim "$line"; line="$GL_TEXT"
  [[ -n "$line" && "$line" != \#* ]] || return 2
  if [[ "$line" =~ ^([a-z_][a-z_0-9]*)(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
  else
    return 2
  fi
  gl_config_index "$key" || return 2
  [[ "$rest" == :* ]] || return 1
  # Nested YAML is outside this format, including indented recognized keys.
  [[ "$1" == "$key":* ]] || return 1
  gl_config_trim "${rest#:}"; GL_VALUE="$GL_TEXT"
  case "$GL_VALUE" in
    \"*|\'*)
      quote="${GL_VALUE:0:1}"
      [[ ${#GL_VALUE} -ge 2 && "${GL_VALUE: -1}" == "$quote" ]] || return 1
      GL_VALUE="${GL_VALUE:1:${#GL_VALUE}-2}" ;;
    \[*|\{*|\|*|\>*) return 1 ;;
  esac
  gl_config_valid_value "$key" "$GL_VALUE"
}

# Read one layer, rejecting ambiguous recognized entries rather than ignoring them.
gl_config_read_layer() {
  local file="$1" layer="$2" line rc number=0 n
  local seen=()
  [[ -f "$file" && -r "$file" ]] || { gl_config_error "cannot read $layer file: $file"; return 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    number=$((number + 1))
    gl_config_parse_line "$line"; rc=$?
    [[ "$rc" != 2 ]] || continue
    [[ "$rc" == 0 ]] || { gl_config_error "$file:$number: malformed recognized setting"; return 1; }
    n="$GL_INDEX"
    [[ "${seen[n]:-}" != true ]] || { gl_config_error "$file:$number: duplicate ${GL_KEYS[n]}"; return 1; }
    seen[n]=true
    if [[ "$layer" == bundled ]]; then
      if [[ -z "$GL_VALUE" ]] && ! gl_config_empty_allowed "${GL_KEYS[n]}"; then
        gl_config_error "$file:$number: empty bundled ${GL_KEYS[n]}"; return 1
      fi
      GL_DEFAULTS[n]="$GL_VALUE"; GL_VALUES[n]="$GL_VALUE"
    else
      GL_PINNED[n]=true
      if [[ -n "$GL_VALUE" ]] || gl_config_empty_allowed "${GL_KEYS[n]}"; then
        GL_VALUES[n]="$GL_VALUE"; GL_SOURCES[n]=user
      fi
    fi
  done < "$file" || { gl_config_error "failed reading $layer file: $file"; return 1; }
  if [[ "$layer" == bundled ]]; then
    for n in "${!GL_KEYS[@]}"; do
      [[ "${seen[n]:-}" == true ]] || { gl_config_error "$file: missing bundled ${GL_KEYS[n]}"; return 1; }
    done
  fi
  return 0
}

# Load both layers and assign CFG_* only after all configuration is usable.
# $1 is the resolved plugin root; $2 optionally selects a user file for validation.
gl_config_load() {
  local n
  GL_CONFIG_FILE="${2:-${HOME}/.config/greenlight/config.yaml}"
  GL_DEFAULTS=(); GL_VALUES=(); GL_SOURCES=(); GL_PINNED=()
  for n in "${!GL_KEYS[@]}"; do GL_SOURCES[n]=bundled; GL_PINNED[n]=false; done
  gl_config_read_layer "$1/references/default-config.yaml" bundled || return 1
  if [[ -e "$GL_CONFIG_FILE" || -L "$GL_CONFIG_FILE" ]]; then
    gl_config_read_layer "$GL_CONFIG_FILE" user || return 1
  fi
  for n in "${!GL_KEYS[@]}"; do printf -v "${GL_VARS[n]}" '%s' "${GL_VALUES[n]}"; done
}
