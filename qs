#!/usr/bin/env bash

set -euo pipefail

# Define some help functions
error() {
  local message

  message="$1"
  echo -e "Error: $message. Exiting..." >&2 && exit 1
}

error_help() {
  local script
  local message
  local help

  script=$(basename "$0")
  message="$1"
  help=$(cat <<EOF
Usage:

  $script <command> [arguments]

The commands are:

  upload     uploads media (filepath is required)
  delete     deletes all media files
  list       prints all uploaded media

Other environments:

  IMGUR_CLIENT_ID   overrides client_id

Examples:

  $script upload '/user/media/example.jpeg'   # Upload example.jpeg to Imgur
  $script delete                              # Removes all uploaded media
  $script list                                # Prints all uploaded media
EOF
)

  echo -e "$help\n" >&2 && error "$message"
}

# Check if all dependencies are in place
type curl &> /dev/null || error "curl not found"
type jq &> /dev/null || error "jq not found"
type exiftool &> /dev/null || error "exiftool not found"

# Define storage file for media
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
media_storage="$dir/.qs-storage.txt"
[[ ! -f "$media_storage" ]] && touch "$media_storage"

# Override default options
default_imgur_client_id=8aecfc6ca13a3ea
imgur_client_id="${IMGUR_CLIENT_ID:=$default_imgur_client_id}"

# Delete command removes
delete() {
  local media_path

  while IFS=$'\t' read -r media_path link deletehash datetime; do
    response=$(curl --silent --show-error --no-progress-meter --fail --location \
      --request 'DELETE' \
      --header "Authorization: Client-ID ${imgur_client_id}" \
      --header "User-Agent: " \
      "https://api.imgur.com/3/image/${deletehash}" || true
    )
    [[ -z "$response" ]] && echo "$media_path not removed" && continue
    echo "$media_path removed"
  done < <(cat "$media_storage")

  echo -n > "$media_storage"
}

upload() {
  [[ $# -lt 1 ]] && error_help "File not passed"

  local media_path
  media_path="$1"

  response=$(
    exiftool -all= -O - "$media_path" \
      | curl --silent --show-error --no-progress-meter --fail --location \
        --request 'POST' \
        --header "Authorization: Client-ID ${imgur_client_id}" \
        --header "User-Agent: " \
        --form "image=@-;filename=dummy" \
        'https://api.imgur.com/3/image'
  )

  deletehash=$(jq -r '.data.deletehash' <<< "$response")
  link=$(jq -r '.data.link' <<< "$response")
  datetime=$(jq -r '.data.datetime' <<< "$response")

  echo -e "$media_path\t$link\t$deletehash\t$datetime" >> "$media_storage"

  echo "Uploaded: $link. Link copied!"
  echo -n "$link" | pbcopy
}

list() {
  echo -e "media_path\tlink\tdeletehash\tdatetime"
  while IFS=$'\t' read -r media_path link deletehash datetime; do
    echo -e "$media_path\t$link\t$deletehash\t$datetime"
  done < <(cat "$media_storage")
}

[[ $# -lt 1 ]] && error_help "No function passed"
fn="$1"
[[ "$fn" != "upload" && "$fn" != "delete" && "$fn" != "list" ]] && error_help "No function '$fn'"
shift
"$fn" "$@"