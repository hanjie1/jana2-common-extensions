#!/usr/bin/env bash
#
# jce.sh:
# Bash counterpart to jce.csh. Wrapper around jana that ensures:
#   - evio_parser is always first in -Pplugins
#   - JCE plugin path is prepended to jana_plugin_path/JANA_PLUGIN_PATH

passthrough_args=()
input_plugins=""
cli_plugin_path=""
cli_default_plugins_file=""

for arg in "$@"; do
    case "$arg" in
        -Pplugins=*)
            input_plugins="$arg"
            ;;
        -Pjana:plugin_path=*)
            cli_plugin_path="$arg"
            ;;
        -PDEFAULT_PLUGINS:FILE=*)
            cli_default_plugins_file="$arg"
            ;;
        *)
            passthrough_args+=("$arg")
            ;;
    esac
done

jce_root="${JCE_HOME:-}"
if [[ -z "$jce_root" ]]; then
    echo "jce.sh error: set JCE_HOME to the root of the JCE installation."
    exit 2
fi

jce_plugin_dir="${jce_root}/lib/plugins"

plugins_value=""
if [[ -n "$input_plugins" ]]; then
    plugins_value="${input_plugins#-Pplugins=}"
    plugins_value=$(echo "$plugins_value" | tr ',' '\n' | sed 's/[[:space:]]//g' | sed '/^$/d' | tr '\n' ',' | sed 's/,$//')
fi

if [[ -n "$cli_default_plugins_file" ]]; then
    default_plugins_file="${cli_default_plugins_file#-PDEFAULT_PLUGINS:FILE=}"
elif [[ -n "${JCE_CONFIG_DIR:-}" ]]; then
    default_plugins_file="${JCE_CONFIG_DIR}/default_plugins.db"
else
    default_plugins_file="${jce_root}/config/default_plugins.db"
fi

default_plugins=""
if [[ -f "$default_plugins_file" ]]; then
    raw_defaults=$(grep -v '^[[:space:]]*#' "$default_plugins_file" | tr ',' '\n' | sed 's/[[:space:]]//g' | sed '/^$/d' | tr '\n' ',' | sed 's/,$//')
    if [[ -n "$raw_defaults" ]]; then
        default_plugins="$raw_defaults"
    fi
fi

if [[ -z "$default_plugins" ]]; then
    default_plugins="evio_parser"
fi

if [[ -n "$plugins_value" ]]; then
    merged_plugins="${default_plugins},${plugins_value}"
else
    merged_plugins="$default_plugins"
fi

user_plugin_path=""
if [[ -z "$cli_plugin_path" ]]; then
    user_plugin_path="${JANA_PLUGIN_PATH:-}"
else
    user_plugin_path="$cli_plugin_path"
    if [[ "$user_plugin_path" == -Pjana:plugin_path=* ]]; then
        user_plugin_path="${user_plugin_path#-Pjana:plugin_path=}"
    else
        echo "jce.sh error: invalid plugin path: $user_plugin_path"
        exit 2
    fi
fi

final_plugin_path="$jce_plugin_dir"
if [[ -n "$user_plugin_path" ]]; then
    final_plugin_path="${final_plugin_path}:${user_plugin_path}"
fi

export JANA_PLUGIN_PATH="$final_plugin_path"

final_args=("${passthrough_args[@]}" "-Pplugins=${merged_plugins}" "-Pjana:plugin_path=${final_plugin_path}")

jana_cmd=""
if [[ -n "${JANA_HOME:-}" && -x "${JANA_HOME}/bin/jana" ]]; then
    jana_cmd="${JANA_HOME}/bin/jana"
fi

if [[ -z "$jana_cmd" ]]; then
    if command -v jana >/dev/null 2>&1; then
        jana_cmd="jana"
    else
        echo "jce.sh error: jana not found."
        echo "Please either:"
        echo "  1) export JANA_HOME=/path/to/jana/install"
        echo "     (so JANA_HOME/bin/jana exists), or"
        echo "  2) add jana to your path:"
        echo '     export PATH="/path/to/jana/bin:${PATH}"'
        exit 2
    fi
fi

exec "$jana_cmd" "${final_args[@]}"
