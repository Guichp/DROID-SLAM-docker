#!/bin/bash

# --- 1. Define Variables and Setup ---
# The default VNC display port is 5900 + display number (e.g., :1 -> 5901)
export DISPLAY=:1
VNC_PORT=5901
WEBSOCKET_PORT=6080
# Location of the noVNC static assets served by websockify.
NOVNC_WEB_ROOT=${NOVNC_WEB_ROOT:-/usr/share/novnc}
# We'll default to 'root' if running as uid 0, or use $USER if it exists.
if [ "$(id -u)" = "0" ]; then
    export USER="root"
fi

# Check for required password (optional, but good practice)
if [ -z "$VNC_PW" ]; then
    echo "ERROR: VNC_PW environment variable is not set."
    exit 1
fi

# --- 2. Configure VNC Server ---
# Create the VNC password file using the VNC_PW environment variable.
# The password file must be secured (chmod 600) and placed in the user's home directory.
mkdir -p /root/.vnc
echo "$VNC_PW" | vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd

# --- 3. Start VNC Server ---
# Start the TightVNC server on display :1.
# Allow overriding geometry and depth through environment variables so Compose settings win.
VNC_RESOLUTION_VALUE=${VNC_RESOLUTION:-1600x1200}
VNC_DEPTH_VALUE=${VNC_DEPTH:-24}

# Kill any stale instance to avoid "already running" errors when restarting the container.
tightvncserver -kill "$DISPLAY" >/dev/null 2>&1 || true
# TightVNC leaves lock files behind; remove them so the next launch succeeds.
rm -f "$HOME/.vnc/"*"${DISPLAY}"* 2>/dev/null || true

tightvncserver "$DISPLAY" -geometry "$VNC_RESOLUTION_VALUE" -depth "$VNC_DEPTH_VALUE" -localhost

# Wait for the VNC server to fully start
sleep 2

# --- 4. Start Websockify ---
echo "Starting websockify on port $WEBSOCKET_PORT, serving ${NOVNC_WEB_ROOT}, forwarding to VNC port $VNC_PORT..."
# Websockify serves the noVNC client assets and tunnels websocket traffic to localhost:5901.
exec websockify --web="$NOVNC_WEB_ROOT" $WEBSOCKET_PORT localhost:$VNC_PORT