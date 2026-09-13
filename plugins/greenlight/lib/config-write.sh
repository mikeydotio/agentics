#!/usr/bin/env bash
# Management-only writes; sourced after config.sh. Readers never acquire locks.

# Release ownership before reporting success; a cleanup error must remain failure.
gl_config_release() {
  rmdir "$GL_WRITE_LOCK" || { gl_config_error "cannot release lock $GL_WRITE_LOCK"; return 1; }
  GL_WRITE_LOCKED=false
}

# Remove only resources this writer owns. EXIT cleanup preserves the failure code.
gl_config_cleanup() {
  local result=$?
  if [[ -n "${GL_WRITE_TEMP:-}" ]]; then
    rm -f "$GL_WRITE_TEMP" || { gl_config_error "cannot remove temporary $GL_WRITE_TEMP"; result=1; }
  fi
  if [[ "${GL_WRITE_LOCKED:-false}" == true ]]; then
    rmdir "$GL_WRITE_LOCK" || { gl_config_error "cannot release lock $GL_WRITE_LOCK"; result=1; }
  fi
  trap - EXIT
  exit "$result"
}

# Apply a validated request while holding an exclusive, non-waiting writer lock.
# Globals GL_EDIT_KEYS/GL_EDIT_VALUE describe the edit; $1 is the operation.
gl_config_write() {
  local operation="$1" directory file line rc key remove_line item found updated=""
  local words=()
  # Ownership never comes from the caller's environment.
  GL_WRITE_TEMP=""; GL_BACKUP=""; GL_WRITE_LOCKED=false
  file="${HOME}/.config/greenlight/config.yaml"
  directory="${file%/*}"
  [[ ! -L "${HOME}/.config" && ! -L "$directory" && ! -L "$file" ]] || {
    gl_config_error "refusing to mutate a symlink configuration path: $file"; return 1;
  }
  umask 077
  mkdir -p "$directory" || { gl_config_error "cannot create $directory"; return 1; }
  GL_WRITE_LOCK="$directory/.config.lock"
  mkdir "$GL_WRITE_LOCK" 2>/dev/null || {
    gl_config_error "cannot acquire writer lock $GL_WRITE_LOCK (busy, abandoned, or unwritable); no changes made"; return 1;
  }
  GL_WRITE_LOCKED=true
  trap gl_config_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  [[ ! -L "$file" ]] || { gl_config_error "refusing to mutate symlink: $file"; return 1; }
  gl_config_load "$PLUGIN_ROOT" || return 1
  if [[ "$operation" == add || "$operation" == remove ]]; then
    gl_config_index "${GL_EDIT_KEYS[0]}" || return 1
    read -r -a words <<< "${GL_VALUES[GL_INDEX]}"
    found=false
    for item in "${words[@]}"; do
      if [[ "$item" == "$GL_EDIT_VALUE" ]]; then
        found=true
        [[ "$operation" != remove ]] || continue
      fi
      updated="${updated:+$updated }$item"
    done
    if [[ "$operation" == add && "$found" == false ]]; then updated="${updated:+$updated }$GL_EDIT_VALUE"; fi
    GL_EDIT_VALUE="$updated"
  fi
  if [[ ! -e "$file" && ( "$operation" == unset || "$operation" == reset ) ]]; then
    gl_config_release || return 1
    jq -n '{ok:true,backup:null}'
    return
  fi
  GL_WRITE_TEMP="$(mktemp "$directory/.config.tmp.XXXXXX")" || { gl_config_error "cannot create temporary in $directory"; return 1; }
  if [[ "$operation" == reset ]]; then
    GL_BACKUP="$(mktemp "$directory/config.yaml.backup.XXXXXX")" || { gl_config_error "cannot create reset backup"; return 1; }
    cp -p "$file" "$GL_BACKUP" || { gl_config_error "cannot copy reset backup to $GL_BACKUP"; return 1; }
  elif [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      remove_line=false
      gl_config_parse_line "$line"; rc=$?
      if [[ "$rc" == 0 ]]; then
        for key in "${GL_EDIT_KEYS[@]}"; do
          [[ "$key" != "${GL_KEYS[GL_INDEX]}" ]] || remove_line=true
        done
      fi
      if [[ "$remove_line" == false ]]; then
        printf '%s\n' "$line" >> "$GL_WRITE_TEMP" || { gl_config_error "cannot write $GL_WRITE_TEMP"; return 1; }
      fi
    done < "$file" || { gl_config_error "cannot read $file during edit"; return 1; }
  fi
  if [[ "$operation" == set || "$operation" == add || "$operation" == remove ]]; then
    printf '%s: "%s"\n' "${GL_EDIT_KEYS[0]}" "$GL_EDIT_VALUE" >> "$GL_WRITE_TEMP" || {
      gl_config_error "cannot write override to $GL_WRITE_TEMP"; return 1;
    }
  fi
  gl_config_load "$PLUGIN_ROOT" "$GL_WRITE_TEMP" || return 1
  mv -f "$GL_WRITE_TEMP" "$file" || { gl_config_error "cannot replace $file; reset backup: ${GL_BACKUP:-none}"; return 1; }
  GL_WRITE_TEMP=""
  gl_config_release || return 1
  jq -n --arg backup "${GL_BACKUP:-}" '{ok:true,backup:(if $backup == "" then null else $backup end)}'
}
