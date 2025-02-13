#!/bin/bash
# docker2lxc.sh - Export Docker container filesystem to an LXC-compatible tarball

RED="\e[31m"
GREEN="\e[32;1m"
YELLOW="\e[33m"
BLUE="\e[34;1m"
RESET="\e[0m"

# Logging helper functions
log_info() {
  echo -e >&2 "${YELLOW}$1${RESET}"
}

log_error() {
  echo -e >&2 "${RED}$1${RESET}"
}

log_success() {
  echo -e >&2 "${GREEN}$1${RESET}"
}

log_usage() {
  echo -e >&2 "${BLUE}$1${RESET}"
}

usage() {
  cat <<EOF
Usage: $0 <image> [output_file]

Description:
  This script exports the filesystem of a Docker container to an LXC-compatible tarball.
  It pulls the specified Docker image, runs a temporary container, exports its root filesystem,
  compresses it using gzip, and then stops the container.

Arguments:
  <image>         The Docker image to be exported.
  [output_file]   (Optional) The name of the output tar.gz file. Defaults to "template.tar.gz" if not specified.
                  Note: When running over an SSH connection, the output file is not used and output goes to stdout.

Options:
  -h, --help      Display this help message and exit.
EOF
  exit 0
}

# Check if the script is running over an SSH connection
is_remote() {
  ps -o comm= $PPID | grep -q sshd
}

check_docker() {
  if ! command -v docker &>/dev/null; then
    if is_remote; then
      log_error "Docker is not installed on the remote machine, aborting."
    else
      log_error "Docker is not installed, aborting."
    fi
    exit 1
  fi
}

pull_image() {
  local image="$1"
  log_info "Pulling Docker image: '$image'..."
  if ! docker pull "$image" >&2; then
    log_error "Image '$image' not found, aborting."
    exit 2
  fi
}

run_container() {
  local image="$1"
  local container_id
  container_id=$(docker run --rm --entrypoint sh -id "$image")
  if [ $? -ne 0 ]; then
    log_error "Incompatible container '$image', aborting."
    exit 3
  fi
  echo "${container_id}"
}

export_filesystem() {
  local container_id="$1"
  local output_file="$2"

  if [ -n "$output_file" ]; then
    log_info "Exporting root filesystem to '$output_file'..."
    docker export "$container_id" | gzip > "$output_file"
  else
    log_info "Exporting root filesystem to stdout..."
    docker export "$container_id" | gzip
  fi
}

cleanup_container() {
  local container_id="$1"
  log_info "Stopping the running container..."
  docker kill "$container_id" >/dev/null
}

main() {
  if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    usage
  fi

  check_docker

  if [ -z "$1" ]; then
    usage
  fi

  local image="$1"
  local output_file=""

  # If not running over SSH, set the output file name
  if ! is_remote; then
    output_file="${2:-template}"
    # Ensure the filename ends with .tar.gz
    output_file="${output_file%.tar.gz}.tar.gz"
  fi

  pull_image "$image"
  local container_id
  container_id=$(run_container "$image")
  export_filesystem "$container_id" "$output_file"
  cleanup_container "$container_id"
  log_success "Done!"
}

main "$@"
