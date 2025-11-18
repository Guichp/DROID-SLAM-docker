#!/bin/bash

# --- 1. Define Variables and Setup ---
# The default VNC display port is 5900 + display number (e.g., :1 -> 5901)
export DISPLAY=:1
VNC_PORT=5901
WEBSOCKET_PORT=6080

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
# Start the VNC server on display :1. 
# -geometry specifies the screen resolution.
# -depth specifies the color depth.
# -localhost restricts VNC access to the local machine (safer, as websockify is the only intended client).
vncserver $DISPLAY -geometry 1280x800 -depth 24 -localhost

# Wait for the VNC server to fully start
sleep 2

# --- 4. Start Websockify ---
echo "Starting websockify on port $WEBSOCKET_PORT, connecting to VNC port $VNC_PORT..."
# Websockify listens on the public port (6080) and tunnels the traffic
# to the VNC server running on localhost:5901.
exec /usr/local/bin/websockify $WEBSOCKET_PORT localhost:$VNC_PORT