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

# detect if URL is a Git repository URL
is_git_url() {
    local url="$1"
    case "$url" in
        https://github.com/*|https://gitlab.com/*|https://bitbucket.org/*|*.git|*git*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# construct authorization header for Git API
get_git_auth_header() {
    local url="$1"
    local token="$2"

    if [ -z "$token" ]; then
        echo ""
        return
    fi

    case "$url" in
        https://github.com/*)
            echo "Authorization: token $token"
            ;;
        https://gitlab.com/*)
            echo "Authorization: Bearer $token"
            ;;
        https://bitbucket.org/*)
            echo "Authorization: Bearer $token"
            ;;
        *)
            # Generic Git token format
            echo "Authorization: Bearer $token"
            ;;
    esac
}

# will download the extension respecting the max download
# duration setting
download_extension() {
    mkdir -p $download_dir
    echo "Downloading the UI extension..."

    # Check if this is a Git repository URL and token is provided
    if is_git_url "$ext_url" && [ -n "$git_token" ]; then
        echo "Detected Git repository URL with authentication token"
        auth_header=$(get_git_auth_header "$ext_url" "$git_token")

        if [ -n "$auth_header" ]; then
            echo "Using authenticated download for private repository"
            curl -Lf --max-time $download_max_sec -H "$auth_header" "$ext_url" -o "$ext_file"
        else
            curl -Lf --max-time $download_max_sec "$ext_url" -o "$ext_file"
        fi
    elif is_git_url "$ext_url" && [ -z "$git_token" ]; then
        echo "WARNING: Git repository URL detected but no EXTENSION_GIT_TOKEN provided"
        echo "This may fail if the repository is private"
        curl -Lf --max-time $download_max_sec "$ext_url" -o "$ext_file"
    else
        # Non-Git URL, use standard download
        curl -Lf --max-time $download_max_sec "$ext_url" -o "$ext_file"
    fi

    # Validate checksum if provided
    if [ "$checksum_url" != "" ]; then
        echo "Validating the UI extension checksum..."

        # Apply same authentication logic for checksum URL if it's also a Git URL
        if is_git_url "$checksum_url" && [ -n "$git_token" ]; then
            auth_header=$(get_git_auth_header "$checksum_url" "$git_token")

            if [ -n "$auth_header" ]; then
                expected_sha=$(curl -Lf -H "$auth_header" "$checksum_url" | grep "$ext_filename" | awk '{print $1;}')
            else
                expected_sha=$(curl -Lf "$checksum_url" | grep "$ext_filename" | awk '{print $1;}')
            fi
        else
            expected_sha=$(curl -Lf "$checksum_url" | grep "$ext_filename" | awk '{print $1;}')
        fi

        current_sha=$(sha256sum $ext_file | awk '{print $1;}')
        if [ "$expected_sha" != "$current_sha" ]; then
            echo "ERROR: extension checksum mismatch"
            echo "Expected: $expected_sha"
            echo "Current:  $current_sha"
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

    if [ -n "$ext_vars" ] && [ -n "$ext_name" ]; then
        create_extension_js_file_with_vars
    fi

    echo "UI extension installed successfully"
}

create_extension_js_file_with_vars() {
  echo "Generating extension vars js file..."
  ext_installed_path=$(find /tmp/extensions/resources -type d -name "extension*-$ext_name*.js" | head -n 1)
  sanitized_extension_name=$(echo "${ext_name//-/_}" | tr '[:lower:]' '[:upper:]')
  ext_js_file_name="${sanitized_extension_name}_vars"
  js_file_path="${ext_installed_path}/extension-0-${ext_js_file_name}.js"
  js_variable=$(echo "$ext_vars" | jq -r 'to_entries | map("\"" + (.key | ascii_upcase) + "\": \"" + .value + "\"") | join(", ")')
  js_vars_wrap="((window) => { const vars = { $js_variable }; window.${sanitized_extension_name}_VARS = vars; })(window);"
  if [ -d "$ext_installed_path" ]; then
      echo "Exporting extension vars file at $js_file_path"
      echo "$js_vars_wrap" > "$js_file_path"
  else
      echo "$ext_installed_path path doesn't exist, extension vars failed to be exported "
  fi
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

# Git token for private repository access
git_token="${EXTENSION_GIT_TOKEN:-}"

checksum_url="${EXTENSION_CHECKSUM_URL:-}"
download_max_sec="${MAX_DOWNLOAD_SEC:-30}"

ext_filename=$(basename -- "$ext_url")
download_dir=`mktemp -d -t extension-XXXXXX`
ext_file="$download_dir/$ext_filename"
if [ -f $ext_file ]; then
    rm $ext_file
fi

ext_vars="${EXTENSION_JS_VARS:-}"
if [ -n "${ext_vars}" ]; then
    ext_vars=$(echo "$ext_vars" | jq -c '.')
fi

# Log authentication status (without exposing token)
if [ -n "$git_token" ]; then
    echo "Git authentication token detected for private repository access"
else
    echo "No Git authentication token provided - public repositories only"
fi

download_extension
install_extension
