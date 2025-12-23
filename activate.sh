#!/bin/bash
# WSL2 ZTNA Proxy Activation Script
# Activates proxy routing through Windows host for ZTNA solutions (venv-style)
# Works with Netskope Private Access, Zscaler ZPA, Cloudflare Access, etc.
#
# Usage: source activate.sh
#        deactivate  (to deactivate)

# Check if already activated
if [ -n "$_PROXY_ACTIVATED" ]; then
    echo "Proxy is already activated. Use 'deactivate' to deactivate first."
    return 1
fi

# Get Windows host IP from WSL2 gateway
WIN_HOST_IP=$(ip route | grep default | awk '{print $3}')

# Fallback for mirrored mode: if gateway detection fails or returns unexpected value,
# try using localhost (works in mirrored mode where WSL2 shares Windows IP)
if [ -z "$WIN_HOST_IP" ] || [[ "$WIN_HOST_IP" == "0.0.0.0" ]]; then
    WIN_HOST_IP="127.0.0.1"
    echo "Note: Using localhost as proxy host (mirrored mode or gateway detection unavailable)"
fi

# Default proxy port
PROXY_PORT=${PROXY_PORT:-3128}

# Save original PS1 if not already saved
if [ -z "$_ORIGINAL_PS1" ]; then
    _ORIGINAL_PS1="$PS1"
fi

# Save original JAVA_OPTS, GRADLE_OPTS, and JAVA_TOOL_OPTIONS if not already saved
if [ -z "$_ORIGINAL_JAVA_OPTS" ]; then
    _ORIGINAL_JAVA_OPTS="$JAVA_OPTS"
fi
if [ -z "$_ORIGINAL_GRADLE_OPTS" ]; then
    _ORIGINAL_GRADLE_OPTS="$GRADLE_OPTS"
fi
if [ -z "$_ORIGINAL_JAVA_TOOL_OPTIONS" ]; then
    _ORIGINAL_JAVA_TOOL_OPTIONS="$JAVA_TOOL_OPTIONS"
fi

# Set proxy environment variables
export http_proxy="http://${WIN_HOST_IP}:${PROXY_PORT}"
export https_proxy="http://${WIN_HOST_IP}:${PROXY_PORT}"
export no_proxy="localhost,127.0.0.1"

# Set Java/Spring Boot proxy properties (if JAVA_HOME is set or java is in PATH)
if command -v java >/dev/null 2>&1 || [ -n "$JAVA_HOME" ]; then
    # Build proxy settings string
    PROXY_SETTINGS="-Dhttp.proxyHost=${WIN_HOST_IP} -Dhttp.proxyPort=${PROXY_PORT} -Dhttps.proxyHost=${WIN_HOST_IP} -Dhttps.proxyPort=${PROXY_PORT} -Dhttp.proxySet=true -Dhttps.proxySet=true -Dhttp.nonProxyHosts=localhost|127.0.0.1"
    
    # Use JAVA_TOOL_OPTIONS (automatically picked up by any JVM - works for Gradle, Maven, direct Java)
    export JAVA_TOOL_OPTIONS="${_ORIGINAL_JAVA_TOOL_OPTIONS} ${PROXY_SETTINGS}"
    
    # Also set JAVA_OPTS and GRADLE_OPTS for compatibility
    export JAVA_OPTS="${_ORIGINAL_JAVA_OPTS} ${PROXY_SETTINGS}"
    export GRADLE_OPTS="${_ORIGINAL_GRADLE_OPTS} ${PROXY_SETTINGS}"
    
    export _JAVA_PROXY_SET=1
fi

# Modify prompt to show (proxy) prefix
export PS1="(proxy) $PS1"

# Mark as activated
export _PROXY_ACTIVATED=1
export _ORIGINAL_PS1
export _ORIGINAL_JAVA_OPTS
export _ORIGINAL_GRADLE_OPTS
export _ORIGINAL_JAVA_TOOL_OPTIONS

# Define deactivate function
deactivate() {
    if [ -z "$_PROXY_ACTIVATED" ]; then
        echo "Proxy is not activated."
        return 1
    fi
    
    # Restore original PS1
    if [ -n "$_ORIGINAL_PS1" ]; then
        export PS1="$_ORIGINAL_PS1"
    fi
    
    # Unset proxy variables
    unset http_proxy
    unset https_proxy
    unset no_proxy
    
    # Restore original JAVA_OPTS, GRADLE_OPTS, and JAVA_TOOL_OPTIONS if they were modified
    if [ -n "$_JAVA_PROXY_SET" ]; then
        if [ -n "$_ORIGINAL_JAVA_OPTS" ]; then
            export JAVA_OPTS="$_ORIGINAL_JAVA_OPTS"
        else
            unset JAVA_OPTS
        fi
        if [ -n "$_ORIGINAL_GRADLE_OPTS" ]; then
            export GRADLE_OPTS="$_ORIGINAL_GRADLE_OPTS"
        else
            unset GRADLE_OPTS
        fi
        if [ -n "$_ORIGINAL_JAVA_TOOL_OPTIONS" ]; then
            export JAVA_TOOL_OPTIONS="$_ORIGINAL_JAVA_TOOL_OPTIONS"
        else
            unset JAVA_TOOL_OPTIONS
        fi
        unset _JAVA_PROXY_SET
        unset _ORIGINAL_JAVA_OPTS
        unset _ORIGINAL_GRADLE_OPTS
        unset _ORIGINAL_JAVA_TOOL_OPTIONS
    fi
    
    # Unset activation marker
    unset _PROXY_ACTIVATED
    unset _ORIGINAL_PS1
    
    # Remove deactivate function
    unset -f deactivate
    
    echo "Proxy deactivated."
}

# Set up auto-deactivation on shell exit
trap 'if [ -n "$_PROXY_ACTIVATED" ]; then deactivate; fi' EXIT

echo "Proxy activated: ${http_proxy}"
echo "Windows host IP: ${WIN_HOST_IP}"
echo "Use 'deactivate' to disable proxy routing."

