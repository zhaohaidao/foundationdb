#!/bin/bash

# Functions to download and start https://github.com/seaweedfs/seaweedfs,
# a blob store with an S3 API.

# Cleanup the mess we've made. For calling from signal trap on exit.
# $1 Weed PID to kill if running.
# $2 The seasweed directory to clean up on exit.
shutdown() {
  local pid="${1}"
  local dir="${2}"
  if [ -n "${pid}" ]; then
    # KILL! If we send SIGTERM, seaweedfs hangs out
    # ten seconds before shutting down (could config.
    # time but just kill it -- there is no state to save).
    kill -9 "${pid}"
  fi
  if [ -d "${dir}" ]; then
    rm -rf "${dir}"
  fi
}

# Download seaweed if not already present.
# $1 The directory to download seaweed into.
# Returns the full path to the weed binary.
# Caller should test $? for error code on return.
download_weed() {
  local dir="${1}"
  local tgz
  local os=
  # Make sure we have curl installed.
  if ! command -v curl &> /dev/null
  then
      echo "ERROR: 'curl' not found."
      exit 1
  fi
  if [[ "$OSTYPE" =~ ^linux ]]; then
    os="linux"
  elif [[ "$OSTYPE" =~ ^darwin ]]; then
    os="darwin"
  else
    echo "ERROR: Unsupported operating system" >&2
    # Return out of this function (does not exit program).
    exit 1
  fi
  tgz="${os}_$(uname -m).tar.gz"
  # If not already present, download it.
  local fullpath_tgz="${dir}/${tgz}"
  if [ ! -f "${fullpath_tgz}" ]; then
    # Change directory because awkward telling curl where to put download.
    ( cd "${dir}" || exit 1 
      curl -sL "https://github.com/seaweedfs/seaweedfs/releases/download/3.79/${tgz}" \
        -o "${tgz}"
      )
  fi
  local weed_binary="${dir}/weed"
  if [ ! -f "${weed_binary}" ]; then
    tar xfz "${fullpath_tgz}" --directory "${dir}"
  fi
  echo "${weed_binary}"
}

# Create directory for weed to use.
# $1 Directory where we want weed to write data and logs.
# Returns the created weed directory. Caller should
# check $? error code on return.
create_weed_dir() {
  local dir="${1}"
  local weed_dir
  weed_dir=$(mktemp -d -p "${dir}")
  # Exit if the temp directory wasn't created successfully.
  if [ ! -d "${weed_dir}" ]; then
    echo "ERROR: Failed create of weed directory ${weed_dir}" >&2
    exit 1
  fi
  echo "${weed_dir}"
}

# Start up the weed server. It can take 30 seconds to come up.
# $1 The full path to the weed binary. 
# $2 The path to the weed directory for logs and data.
# Returns pid of started procdess and the s3 port.
# Caller should test return $? value.
start_weed() {
  local binary="${1}"
  local weed_dir="${2}"
  local master_port=9333
  local s3_port=8333
  local volume_port_grpc=18080
  local volume_port=8080
  local filer_port=8888
  local max=10
  local index
  for index in $(seq 1 ${max}); do
    # Increment port numbers each time through -- even the first time
    # to get past defaults.
    ((master_port=master_port+1))
    ((s3_port=s3_port+1))
    ((volume_port=volume_port+1))
    ((volume_port_grpc=volume_port_grpc+1))
    ((filer_port=filer_port+1))
    # Start weed in background.
    "${binary}" -logdir="${weed_dir}" server -dir="${weed_dir}" \
      -s3 -ip=localhost -master.port="${master_port}" -s3.port="${s3_port}" \
      -volume.port.grpc="${volume_port_grpc}" -volume.port="${volume_port}" \
      -filer.port="${filer_port}" &> /dev/null &
    # Pick up the weed pid.
    local weed_pid=$!
    # Loop while process is coming up. It can take 25 seconds.
    while  kill -0 ${weed_pid} &> /dev/null; do
      if grep "Start Seaweed S3 API Server" "${weed_dir}/weed.INFO" &> /dev/null ; then
        # Its up and running. Breakout of this while loop and the wrapping 'for' loop
        # (hence the '2' in the below)
        break 2
      fi
      sleep 5
    done
    # The process died. If it was because of port clash, go around again w/ new ports.
    if grep "bind: address already in use" "${weed_dir}/weed.INFO" &> /dev/null ; then
      # Clashed w/ existing port. Go around again and get new ports.
      :
    else
      # Seaweed is not up and it is not because of port clash. Exit.
      # Dump out the tail of the weed log because its going to get cleaned up when
      # we exit this script. Give the user an idea of what went wrong.
      if [ -f "${weed_dir}/weed.INFO" ]; then
        tail -50 "${weed_dir}/weed.INFO" >&2
      fi
      echo "ERROR: Failed to start weed" >&2
      exit 1
    fi
  done
  if [ "${index}" -ge "${max}" ]; then
    echo "ERROR: Ran out of retries (${index})"
    exit 1
  fi
  # Check server is up from client's perspective. Get a file id (fid) and volume URL.
  if ! curl -s "http://localhost:${master_port}/dir/assign" | grep fid &> /dev/null; then
    echo "ERROR: Failed to curl fid" >&2
    exit 1
  fi
  # Return two values.
  echo "${weed_pid}"
  echo "${s3_port}"
}
