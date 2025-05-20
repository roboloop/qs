#!/usr/bin/env bash

set -euo pipefail

# Define some help functions
qs=$(basename "$0")
error() {
  local message

  message="$1"
  echo -e "Error: ${message}. Exiting..." >&2 && exit 1
}

error_help() {
  local message help

  message="$1"
  help=$(cat <<EOF
Usage:

  ${qs} <command> [arguments]

The commands are:

  upload      uploads media (filepath, url, or stdin media is accepted)
    --no-copy to skip copying the result link
  delete      deletes all media files
  list        prints all uploaded media

Other environments:

  IMGUR_CLIENT_ID   overrides client_id

Examples:

  ${qs} upload '/user/media/example.jpeg'   # Upload example.jpeg to Imgur
  ${qs} delete                              # Removes all uploaded media
  ${qs} list                                # Prints all uploaded media
EOF
)

  echo -e "${help}\n" >&2 && error "${message}"
}

# Check if all dependencies are in place
command -v curl &> /dev/null || error "curl not found"
command -v exiftool &> /dev/null || error "exiftool not found"

# Define storage file for media
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
media_storage="${dir}/.qs-storage.txt"
[[ ! -f "${media_storage}" ]] && touch "${media_storage}"

# Override default options
default_imgur_client_id=8aecfc6ca13a3ea
imgur_client_id="${IMGUR_CLIENT_ID:=${default_imgur_client_id}}"

notify() {
  local text="$1"

  (
    command -v notify-send && notify-send "${qs}" "${text}"
    command -v osascript && osascript -e "display notification \"${text}\" with title \"${qs}\""
  ) &> /dev/null
}

copy() {
  local text="$1"

  echo -n "${text}" | (
    command -v xclip && xclip -selection clipboard && return
    command -v xsel && xsel --clipboard && return
    command -v pbcopy && pbcopy && return
  ) &> /dev/null
}

# Delete command removes
delete() {
  local media_path user_url response

  while IFS=$'\t' read -r media_path link deletehash; do
    response=$(curl --silent --show-error --no-progress-meter --fail --location \
      --request 'DELETE' \
      --header "Authorization: Client-ID ${imgur_client_id}" \
      --header "User-Agent: " \
      "https://api.imgur.com/3/image/${deletehash}" || true
    )
    user_url="https://imgur.com/delete/${deletehash}"
    [[ -z "${response}" ]] && echo "${media_path} (${user_url}) upload not removed" && continue
    echo "${media_path} upload removed"
  done < "${media_storage}"

  echo -n > "${media_storage}"
}

upload() {
  local no_copy=

  [[ $# -ge 1 && "${1}" == "--no-copy" ]] && no_copy=1 && shift
  [[ $# -eq 0 && -t 0 ]] && error_help "File not passed"

  local deletehash link prepend response
  local media_path="${1:--}"

  if [[ "${media_path}" == https://* ]]; then
    prepend="curl --silent --show-error --fail --location \"${media_path}\""
  elif [[ -e "${media_path}" && -r "${media_path}" || ! -t 0 ]]; then
    prepend="cat \"${media_path}\""
  else
    error_help "File '${media_path}' not found"
  fi

  response=$(
    eval "${prepend}" | \
    exiftool -all= -O - - \
      | curl --silent --show-error --fail --location \
        --request 'POST' \
        --header "Authorization: Client-ID ${imgur_client_id}" \
        --header "User-Agent: " \
        --form "image=@-;filename=dummy" \
        'https://api.imgur.com/3/image'
  )

  deletehash=$(sed -E 's/^.+"deletehash":"([^"]+)".+$/\1/' <<< "${response}")
  link=$(sed -E 's/^.+"link":"([^"]+)".+$/\1/' <<< "${response}")
  echo -e "${media_path}\t${link}\t${deletehash}" >> "${media_storage}"

  echo "Media uploaded!" 1>&2
  echo "${link}"
  ([[ -z "${no_copy}" ]] && copy "${link}" && echo "Link copied!" 1>&2 && notify "Link copied!") || true
}

list() {
  echo -e "media_path\tlink\tdeletehash"
  while IFS=$'\t' read -r media_path link deletehash; do
    echo -e "${media_path}\t${link}\t${deletehash}"
  done < "${media_storage}"
}

[[ $# -lt 1 ]] && error_help "No function passed"
fn="$1"
[[ "${fn}" != "upload" && "${fn}" != "delete" && "${fn}" != "list" ]] && error_help "No function '${fn}'"
shift
"${fn}" "$@"
