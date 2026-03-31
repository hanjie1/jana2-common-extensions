#!/bin/csh -f

# jce.csh: (bash equivalent: jce.sh)
# jce.csh:
# Wrapper around jana that ensures:
#   - evio_parser is always first in -Pplugins
#   - JCE plugin path is prepended to jana_plugin_path/JANA_PLUGIN_PATH

set passthrough_args = ()
set input_plugins = ""
set cli_plugin_path = ""
set cli_default_plugins_file = ""
foreach arg ($argv)
    if ("$arg" =~ "-Pplugins=*") then
        set input_plugins = "$arg"
    else if ("$arg" =~ "-Pjana:plugin_path=*") then
        set cli_plugin_path = "$arg"
    else if ("$arg" =~ "-PDEFAULT_PLUGINS:FILE=*") then
        set cli_default_plugins_file = "$arg"
    else
        set passthrough_args = ($passthrough_args "$arg")
    endif
end

# Resolve JCE install path for plugins.
set jce_root = ""
if ($?JCE_HOME) then
    set jce_root = "$JCE_HOME"
endif

if ("$jce_root" == "") then
    echo "jce.csh error: set JCE_HOME to the root of the JCE installation."
    exit 2
endif

set jce_plugin_dir = "${jce_root}/lib/plugins"

# Extract plugin list (if user passed -Pplugins=...).
set plugins_value = ""
if ("$input_plugins" == "") then
    set plugins_value = ""
else
    set plugins_value = "$input_plugins"
    set plugins_value = "$plugins_value:s/-Pplugins=//"
    # Normalize list formatting and drop empty entries.
    set plugins_value = `echo "$plugins_value" | tr ',' '\n' | sed 's/[[:space:]]//g' | sed '/^$/d' | tr '\n' ',' | sed 's/,$//'`
endif

# Resolve default plugins file path
set default_plugins_file = ""

if ("$cli_default_plugins_file" != "") then
    set default_plugins_file = "$cli_default_plugins_file:s/-PDEFAULT_PLUGINS:FILE=//"
else if ($?JCE_CONFIG_DIR) then
    set default_plugins_file = "$JCE_CONFIG_DIR/default_plugins.db"
else
    set default_plugins_file = "$jce_root/config/default_plugins.db"
endif

# Load default plugins.
set default_plugins = ""
if (-f "$default_plugins_file") then
    # Remove comments, trim whitespace, and collapse into one line
    set raw_defaults = `grep -v '^[[:space:]]*#' "$default_plugins_file" | tr ',' '\n' | sed 's/[[:space:]]//g' | sed '/^$/d' | tr '\n' ',' | sed 's/,$//'`

    if ("$raw_defaults" != "") then
        set default_plugins = "$raw_defaults"
    endif
endif

# Fallback to evio_parser if default plugins file is missing or empty
if ("$default_plugins" == "") then
    set default_plugins = "evio_parser"
endif

# Merge default plugins with user-specified plugins
if ("$plugins_value" != "") then
    set merged_plugins = "$default_plugins,$plugins_value"
else
    set merged_plugins = "$default_plugins"
endif

# Determine user plugin-path source:
#   1) -Pjana:plugin_path=...
#   2) existing JANA_PLUGIN_PATH env var
set user_plugin_path = ""
if ("$cli_plugin_path" == "") then
    if ($?JANA_PLUGIN_PATH) then
        set user_plugin_path = "$JANA_PLUGIN_PATH"
    endif
else
    set user_plugin_path = "$cli_plugin_path"
    if ("$user_plugin_path" =~ "-Pjana:plugin_path=*") then
        set user_plugin_path = "$user_plugin_path:s/-Pjana:plugin_path=//"
    else
        echo "jce.csh error: invalid plugin path: $user_plugin_path"
        exit 2
    endif
endif

set final_plugin_path = "$jce_plugin_dir"
if ("$user_plugin_path" == "") then
    set final_plugin_path = "$jce_plugin_dir"
else
    set final_plugin_path = "${final_plugin_path}:${user_plugin_path}"
endif

# Export merged plugin path and pass merged params to jana.
setenv JANA_PLUGIN_PATH "$final_plugin_path"

set final_args = ($passthrough_args "-Pplugins=${merged_plugins}" "-Pjana:plugin_path=${final_plugin_path}")

set jana_cmd = ""
if ($?JANA_HOME) then
    if (-x "$JANA_HOME/bin/jana") then
        set jana_cmd = "$JANA_HOME/bin/jana"
    endif
endif

if ("$jana_cmd" == "") then
    which jana >& /dev/null
    if ($status == 0) then
        set jana_cmd = "jana"
    else
        echo "jce.csh error: jana not found."
        echo "Please either:"
        echo "  1) setenv JANA_HOME /path/to/jana/install"
        echo "     (so JANA_HOME/bin/jana exists), or"
        echo "  2) add jana to your path:"
        echo '     setenv PATH "/path/to/jana/bin:${PATH}"'
        exit 2
    endif
endif

exec "$jana_cmd" $final_args
