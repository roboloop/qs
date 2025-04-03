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
  local message
  local help

  message="$1"
  help=$(cat <<EOF
Usage:

  ${qs} <command> [arguments]

The commands are:

  upload     uploads media (filepath is required)
  delete     deletes all media files
  list       prints all uploaded media

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
command -v jq &> /dev/null || error "jq not found"
command -v exiftool &> /dev/null || error "exiftool not found"

# Define storage file for media
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
media_storage="${dir}/.qs-storage.txt"
[[ ! -f "${media_storage}" ]] && touch "${media_storage}"

# Override default options
default_imgur_client_id=8aecfc6ca13a3ea
imgur_client_id="${IMGUR_CLIENT_ID:=${default_imgur_client_id}}"

notify() {
  local text
  text="$1"

  (
    command -v notify-send && notify-send "${qs}" "${text}"
    command -v osascript && osascript -e "display notification \"${text}\" with title \"${qs}\""
  ) &> /dev/null
}

copy() {
  local text
  text="$1"

  echo -n "${text}" | (
    command -v xclip && xclip -selection clipboard && return
    command -v xsel && xsel --clipboard && return
    command -v pbcopy && pbcopy && return
  ) &> /dev/null
}

# Delete command removes
delete() {
  local media_path
  local user_url

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
  [[ $# -lt 1 ]] && error_help "File not passed"

  local media_path
  local deletehash
  local link
  media_path="$1"

  response=$(
    exiftool -all= -O - "${media_path}" \
      | curl --silent --show-error --no-progress-meter --fail --location \
        --request 'POST' \
        --header "Authorization: Client-ID ${imgur_client_id}" \
        --header "User-Agent: " \
        --form "image=@-;filename=dummy" \
        'https://api.imgur.com/3/image'
  )

  deletehash=$(jq -r '.data.deletehash' <<< "${response}")
  link=$(jq -r '.data.link' <<< "${response}")
  echo -e "${media_path}\t${link}\t${deletehash}" >> "${media_storage}"

  echo "Media uploaded: ${link}"
  (copy "${link}" && echo "Link copied!" && notify "Link copied!") || true
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
