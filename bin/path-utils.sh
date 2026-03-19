#!/usr/bin/env bash

pu_normalize_slashes() {
  local p=${1-}
  p=${p//\\//}
  printf '%s' "$p"
}

pu_is_windows_abs() {
  [[ ${1-} =~ ^[A-Za-z]:/ ]]
}

pu_is_unc() {
  # After normalization: \\server\share -> //server/share
  [[ ${1-} == //* ]]
}

pu__lc() {
  printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]'
}

pu__host_pwd_variants() {
  local host_pwd=${1-}
  host_pwd="$(pu_normalize_slashes "$host_pwd")"
  host_pwd=${host_pwd%/}

  printf '%s\n' "$host_pwd"

  # WSL style: /mnt/c/Users/me/repo -> C:/Users/me/repo
  if [[ "$host_pwd" =~ ^/mnt/([A-Za-z])/(.*)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}:/${BASH_REMATCH[2]}"
  fi

  # Git Bash / MSYS2 style: /c/Users/me/repo -> C:/Users/me/repo
  if [[ "$host_pwd" =~ ^/([A-Za-z])/(.*)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}:/${BASH_REMATCH[2]}"
  fi
}

pu_hostpath_to_work() {
  local arg=${1-}
  local p
  p="$(pu_normalize_slashes "$arg")"

  if pu_is_unc "$p"; then
    echo "ERROR: Path is outside the current working directory: $arg" >&2
    exit 2
  fi

  if ! pu_is_windows_abs "$p"; then
    printf '%s' "$p"
    return 0
  fi

  if [[ -z "${PU_HOST_PWD-}" ]]; then
    echo "ERROR: PU_HOST_PWD is required to normalize Windows absolute paths." >&2
    exit 2
  fi

  local p_lc
  p_lc="$(pu__lc "$p")"

  local host
  while IFS= read -r host; do
    host=${host%/}
    if [[ -z "$host" ]]; then
      continue
    fi

    local host_lc host_prefix host_prefix_lc
    host_lc="$(pu__lc "$host")"
    host_prefix="${host}/"
    host_prefix_lc="${host_lc}/"

    if [[ "$p_lc" == "$host_lc" ]]; then
      printf '%s' "/work"
      return 0
    fi

    if [[ "$p_lc" == "$host_prefix_lc"* ]]; then
      local rel="${p:${#host_prefix}}"
      if [[ -z "$rel" ]]; then
        printf '%s' "/work"
      else
        printf '%s' "/work/$rel"
      fi
      return 0
    fi
  done < <(pu__host_pwd_variants "$PU_HOST_PWD")

  echo "ERROR: Path is outside the current working directory: $arg" >&2
  exit 2
}
