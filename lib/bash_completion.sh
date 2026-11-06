#!/usr/bin/env bash
# Embedded by the completion and init generators; keep cached output self-contained.

# Fill COMPREPLY with safely quoted candidates matching the typed prefix.
# Decode only quoting syntax in the prefix; never evaluate shell expansions.
# Escape each candidate for the active single/double/unquoted context.
# Candidates are newline-separated literal strings, including path-derived text.
_git_gtr_quote_targets() {
  local raw_prefix="$1" prefix="" quote="" before_quote="" escaped=0 char i
  local branch candidates="$2" quoted fragment ansi=0 dollar=0 was_dollar
  local single_escape="'\\''" ansi_escape="\\'"
  local dollar_escape='\$' tick_escape='\`' double_escape='\"' history_escape='"\!"'
  for ((i=0; i<${#raw_prefix}; i++)); do
    char="${raw_prefix:i:1}"
    was_dollar="$dollar"
    dollar=0
    if [ "$escaped" -eq 1 ]; then
      # Double quotes only consume backslashes before these shell characters.
      if [ "$quote" = '"' ]; then
        case "$char" in
          '"'|'$'|'`'|"\\") ;;
          *) prefix+="\\" ;;
        esac
      fi
      prefix+="$char"
      escaped=0
    elif [ "$char" = "$quote" ]; then
      quote=""
      before_quote=""
      ansi=0
    elif [ "$quote" = "'" ]; then
      if [ "$ansi" -eq 1 ] && [ "$char" = "\\" ]; then
        escaped=1
      else
        prefix+="$char"
      fi
    else
      case "$char" in
        "\\") escaped=1 ;;
        "'"|'"')
          if [ -z "$quote" ]; then
            if [ "$char" = "'" ] && [ "$was_dollar" -eq 1 ]; then
              ansi=1
              prefix="${prefix%?}"
            fi
            quote="$char"
            before_quote="$prefix"
          else
            prefix+="$char"
          fi
          ;;
        '$') prefix+="$char"; [ -n "$quote" ] || dollar=1 ;;
        *) prefix+="$char" ;;
      esac
    fi
  done
  COMPREPLY=()
  # compgen -W evaluates its word list; treat branch names as literal data instead.
  while IFS= read -r branch; do
    printf -v quoted '%q' "$branch"
    if [[ -n "$branch" && ( "$branch" == "$prefix"* || "$quoted" == "$raw_prefix"* ) ]]; then
      # Readline retains text before an opening quote within the current word.
      fragment="${branch#"$before_quote"}"
      case "$quote" in
        "'")
          if [ "$ansi" -eq 1 ]; then
            # Literal replacement works on Bash 3.2 and with patsub_replacement.
            quoted="${fragment//\\/\\\\}"
            quoted="${quoted//\'/$ansi_escape}"
          else
            quoted="${fragment//\'/$single_escape}"
          fi
          quoted+="'"
          ;;
        '"')
          # Escape existing backslashes before adding escapes for shell syntax.
          quoted="${fragment//\\/\\\\}"
          quoted="${quoted//\$/$dollar_escape}"
          quoted="${quoted//\`/$tick_escape}"
          quoted="${quoted//\"/$double_escape}"
          # Leave double quotes to escape history expansion without adding a backslash.
          quoted="${quoted//!/$history_escape}"
          quoted+='"'
          ;;
      esac
      COMPREPLY+=("$quoted")
    fi
  done <<EOF
$candidates
EOF
  # Candidates are already escaped; avoid a second quoting pass on newer Bash.
  builtin compopt +o fullquote 2>/dev/null || true
  builtin compopt -o noquote +o filenames 2>/dev/null || true
}
