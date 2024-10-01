#!/bin/sh

set -euox pipefail

# will return the current system uptime in milliseconds
uptime_ms() {
    # this is necessary to be able to return a value with milliseconds
    # precision as busybox 'date' command does not support %N format
    read up rest </proc/uptime
    echo $(( 10 * (${up%.*}${up#*.}) ))
}

start_time=$(uptime_ms)

finalizer() {
    local dl="${download_dir:-}"
    if [ -d "$dl" ]; then
      rm -rf $dl
    fi
    code=$?
    if [ $code -ne 0 ]; then
        echo "ERROR: failed to install $ext_name extension: error code: $code"
    fi
    end_time=$(uptime_ms)
    elapsed=$(( end_time-start_time ))
    echo "Elapsed Time: $elapsed ms"
    exit 0
}
trap finalizer EXIT

# will download the extension respecting the max download
# duration setting
download_extension() {
    mkdir -p $download_dir
    echo "Downloading the UI extension..."
    curl -Lf --max-time $download_max_sec $ext_url -o $ext_file
    if [ "$checksum_url" != "" ]; then
        echo "Validating the UI extension checksum..."
        expected_sha=$(curl -Lf $checksum_url | grep "$ext_filename" | awk '{print $1;}')
        current_sha=$(sha256sum $ext_file | awk '{print $1;}')
        if [ "$expected_sha" != "$current_sha" ]; then
            echo "ERROR: extension checksum mismatch"
            exit 1
        fi
    fi
    echo "UI extension downloaded successfully"
}

install_extension() {
    echo "Installing the UI extension..."
    cd $download_dir
    local mime_type=$(file --mime-type "$ext_filename" | awk '{print $2}')
    if [ "$mime_type" = "application/gzip" ]; then
        tar -zxf $ext_filename
    elif [ "$mime_type" = "application/x-tar" ]; then
        tar -xf $ext_filename
    else
        echo "error: unsupported extension archive: $mime_type"
        echo "supported formats: gzip and tar"
        exit 1
    fi
    if [ ! -d "/tmp/extensions/resources" ]; then
        mkdir -p /tmp/extensions/resources
    fi
    cp -Rf resources/* /tmp/extensions/resources/
    echo "UI extension installed successfully"
}


## Script
ext_enabled="${EXTENSION_ENABLED:-true}"
ext_name="${EXTENSION_NAME:-}"

if [ "$ext_enabled" != "true" ]; then
    echo "$ext_name extension is disabled"
    exit 0
fi

ext_version="${EXTENSION_VERSION:-}"
ext_url="${EXTENSION_URL:-}"
if [ "$ext_url" = "" ]; then
    echo "error: the env var EXTENSION_URL must be provided"
    exit 1
fi
checksum_url="${EXTENSION_CHECKSUM_URL:-}"
download_max_sec="${MAX_DOWNLOAD_SEC:-30}"

vars="${VARS:-}"
echo "$vars" | jq '.' > /tmp/extensions/resources/$ext_filename/vars.json

ext_filename=$(basename -- "$ext_url")
download_dir=`mktemp -d -t extension-XXXXXX`
ext_file="$download_dir/$ext_filename"
if [ -f $ext_file ]; then
    rm $ext_file
fi
download_extension
install_extension
