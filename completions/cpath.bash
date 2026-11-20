# shellcheck shell=bash
# Bash completion script for cpath
# Auto-loaded from: ${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/cpath
# Or source directly in ~/.bashrc: source /path/to/completions/cpath.bash

_cpath_add_unique_reply() {
  local candidate="$1"
  local existing
  for existing in ${COMPREPLY[@]+"${COMPREPLY[@]}"}; do
    if [ "$existing" = "$candidate" ]; then
      return 0
    fi
  done
  COMPREPLY+=("$candidate")
}

# Legacy Bash (without compopt) registers with -o nospace so directories don't get a
# trailing space; append a space to unique non-directory matches so completion feels native.
_cpath_finalize_nospace_reply() {
  if ! type compopt >/dev/null 2>&1 && [ "${#COMPREPLY[@]}" -eq 1 ]; then
    case "${COMPREPLY[0]}" in
      *" "|*"/"|*"=") ;;
      *) COMPREPLY[0]="${COMPREPLY[0]} " ;;
    esac
  fi
}

_cpath_complete_hosts() {
  local prefix="$1"
  local prepend="${2:-}"
  local host_file="${XDG_CONFIG_HOME:-$HOME/.config}/cpath/host"
  local saved_host sys_host line word i
  local -a words=()

  COMPREPLY=()

  if [ -s "$host_file" ]; then
    saved_host=$(tr -d '\r\n' < "$host_file")
    case "$saved_host" in
      ""|*[[:space:]]*|*[[:cntrl:]]*) ;;
      "$prefix"*) _cpath_add_unique_reply "${prepend}${saved_host}" ;;
    esac
  fi

  sys_host=$(hostname 2>/dev/null || uname -n 2>/dev/null || true)
  case "$sys_host" in
    ""|*[[:space:]]*|*[[:cntrl:]]*) ;;
    "$prefix"*) _cpath_add_unique_reply "${prepend}${sys_host}" ;;
  esac

  if [ -r "$HOME/.ssh/config" ]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      # Split with read -r -a so glob patterns like "Host *" never expand local filenames
      IFS=$' \t' read -r -a words <<< "$line"
      if [ "${#words[@]}" -ge 2 ]; then
        case "${words[0]}" in
          [Hh][Oo][Ss][Tt])
            for ((i = 1; i < ${#words[@]}; i++)); do
              word="${words[$i]}"
              case "$word" in
                *'*'*|*'?'*|!*|'') continue ;;
                "$prefix"*) _cpath_add_unique_reply "${prepend}${word}" ;;
              esac
            done
            ;;
        esac
      fi
    done < "$HOME/.ssh/config"
  fi

  _cpath_finalize_nospace_reply
}

_cpath_complete_static() {
  local prefix="$1"
  shift
  local opt
  COMPREPLY=()
  for opt in "$@"; do
    case "$opt" in
      "$prefix"*) COMPREPLY+=("$opt") ;;
    esac
  done
  _cpath_finalize_nospace_reply
}

# Decode literal characters for filename lookup without evaluating shell input.
_cpath_unescape_word() {
  local s="$1"
  local out="" quote="" i=0 len="${#s}" ch next
  while [ "$i" -lt "$len" ]; do
    if [ -z "$quote" ] && [ "${s:$i:5}" = "\$'\\n'" ]; then
      out+=$'\n'
      i=$((i + 5))
      continue
    fi
    ch="${s:$i:1}"
    if [ -n "$quote" ] && [ "$ch" = "$quote" ]; then
      quote=""
    elif [ -z "$quote" ] && { [ "$ch" = "'" ] || [ "$ch" = '"' ]; }; then
      quote="$ch"
    elif [ "$ch" = "\\" ] && [ "$quote" != "'" ] && [ $((i + 1)) -lt "$len" ]; then
      next="${s:$((i + 1)):1}"
      i=$((i + 1))
      if [ "$next" != $'\n' ]; then
        if [ "$quote" = '"' ]; then
          case "$next" in
            "\\"|'"'|'$'|'`') ;;
            *) out+="\\" ;;
          esac
        fi
        out+="$next"
      fi
    else
      out+="$ch"
    fi
    i=$((i + 1))
  done
  REPLY="$out"
}

# Shell-quote a filename while keeping any prefix before a newline intact
_cpath_quote_filename() {
  local s="$1" quote="${2:-}"
  local out="" chunk q
  # Readline retains the opening quote, so escape only its contents here.
  case "$quote" in
    "'")
      local apostrophe="'\\''"
      REPLY=${s//\'/$apostrophe}
      return 0
      ;;
    '"')
      s="${s//\\/\\\\}"
      s="${s//\"/\\\"}"
      s="${s//\$/\\\$}"
      s="${s//\`/\\\`}"
      local bang="\"'!'\""
      REPLY=${s//\!/$bang}
      return 0
      ;;
  esac
  while :; do
    case "$s" in
      *$'\n'*)
        chunk="${s%%$'\n'*}"
        s="${s#*$'\n'}"
        if [ -n "$chunk" ]; then
          printf -v q '%q' "$chunk"
          out+="$q"
        fi
        out+="\$'\\n'"
        ;;
      *)
        if [ -n "$s" ]; then
          printf -v q '%q' "$s"
          out+="$q"
        fi
        break
        ;;
    esac
  done
  REPLY="$out"
}

_cpath_complete_files() {
  local cur="$1"
  if type compopt >/dev/null 2>&1; then
    # Enable native filename completion only for this positional path argument
    compopt -o bashdefault -o default 2>/dev/null || true
    COMPREPLY=()
    return 0
  fi

  # Readline replaces only the text after an opening quote. COMP_WORDS also
  # includes the earlier characters, which are needed to find the directory.
  local REPLY="" word="${2-$cur}" quote="" kept_path=""
  local kept="${cur%"$word"}"
  case "$kept" in
    *\"|*\')
      quote="${kept: -1}"
      _cpath_unescape_word "$kept"
      kept_path="$REPLY"
      ;;
  esac
  _cpath_unescape_word "$cur"
  local raw_cur="$REPLY"
  local dir_prefix="" base_prefix="$raw_cur" search_dir home_prefix=""

  case "$raw_cur" in
    */*)
      dir_prefix="${raw_cur%/*}/"
      base_prefix="${raw_cur##*/}"
      ;;
  esac

  # Expand these prefixes for lookup only; escaped and single-quoted forms are literal.
  if [[ "$cur" == \~/* ]]; then
    home_prefix=\~/
  else
    # shellcheck disable=SC2016
    case "${cur#\"}" in
      '$HOME/'*|'$HOME"/'*) home_prefix='$HOME/' ;;
      '${HOME}/'*|'${HOME}"/'*) home_prefix='${HOME}/' ;;
    esac
  fi
  search_dir="$dir_prefix"
  if [ -n "$home_prefix" ]; then
    search_dir="$HOME/${dir_prefix#"$home_prefix"}"
  fi

  local display_home="$home_prefix"
  if [ -z "$quote" ] && [[ "$home_prefix" == '$'* ]]; then
    # A variable expansion outside quotes would split a HOME containing spaces.
    display_home="\"${home_prefix%/}\"/"
  fi
  local entry spelling quoted
  COMPREPLY=()
  while IFS= read -r -d '' entry; do
    spelling="$dir_prefix${entry#"$search_dir"}"
    spelling="${spelling#"$kept_path"}"
    if [ -n "$home_prefix" ] && [[ "$spelling" == "$home_prefix"* ]]; then
      _cpath_quote_filename "${spelling#"$home_prefix"}" "$quote"
      quoted="$display_home$REPLY"
    else
      _cpath_quote_filename "$spelling" "$quote"
      quoted="$REPLY"
    fi
    if [ -d "$entry" ]; then
      quoted+="/"
    fi
    COMPREPLY+=("$quoted")
  done < <(
    # Isolate glob options from the interactive shell and preserve filename bytes.
    shopt -u failglob dotglob
    shopt -s nullglob
    for entry in "$search_dir$base_prefix"*; do
      printf '%s\0' "$entry"
    done
  )

  if [ -z "$quote" ]; then
    _cpath_finalize_nospace_reply
  elif [ "${#COMPREPLY[@]}" -eq 1 ]; then
    # Readline cannot distinguish an escaped final quote in a name from a closing quote.
    COMPREPLY[0]+="$quote"
  fi
}

_cpath_completions() {
  local cur prev prev2 i
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev=""
  prev2=""
  if [ "$COMP_CWORD" -gt 0 ]; then
    prev="${COMP_WORDS[COMP_CWORD-1]}"
  fi
  if [ "$COMP_CWORD" -gt 1 ]; then
    prev2="${COMP_WORDS[COMP_CWORD-2]}"
  fi

  # After "--", only complete filenames
  for ((i = 1; i < COMP_CWORD; i++)); do
    if [ "${COMP_WORDS[$i]}" = "--" ]; then
      _cpath_complete_files "$cur" "${2-$cur}"
      return 0
    fi
  done

  # Handle Readline's default "=" word break:
  #   cpath --set-host=<TAB>     -> prev="--set-host", cur="="
  #   cpath --set-host=pro<TAB>  -> prev2="--set-host", prev="=", cur="pro"
  if [ "$prev2" = "--set-host" ] && [ "$prev" = "=" ]; then
    _cpath_complete_hosts "$cur"
    return 0
  fi

  if [ "$prev" = "--set-host" ]; then
    if [ "$cur" = "=" ]; then
      _cpath_complete_hosts ""
    else
      _cpath_complete_hosts "$cur"
    fi
    return 0
  fi

  # Bash 3.2 can report the full token in COMP_WORDS while Readline replaces
  # only the suffix after "=". The callback's second argument is that span.
  # When "=" is not a word break, replace the full token instead.
  case "$cur" in
    --set-host=*)
      case "${2-$cur}" in
        --set-host=*) _cpath_complete_hosts "${cur#--set-host=}" "--set-host=" ;;
        *) _cpath_complete_hosts "${cur#--set-host=}" ;;
      esac
      return 0
      ;;
    --*)
      _cpath_complete_static "$cur" --help --version --set-host --clear-host
      return 0
      ;;
    -*)
      _cpath_complete_static "$cur" -d -s -u -n -p -h -v --help --version --set-host --clear-host
      return 0
      ;;
  esac

  # Complete filesystem paths only in path-argument positions
  _cpath_complete_files "$cur" "${2-$cur}"
}

if type compopt >/dev/null 2>&1; then
  complete -F _cpath_completions cpath
else
  # Bash 3.2 lacks compopt; -o nospace lets directories end with '/' without adding a
  # trailing space while keeping host aliases untouched (no -o filenames / -o default).
  complete -o nospace -F _cpath_completions cpath
fi
