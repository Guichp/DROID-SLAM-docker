#!/bin/bash

# Navigate to the project root directory (parent of scripts/)
cd "$(dirname "$0")/.."

# webots container name
container="drones_webots-sim" # this should match the container_name in docker-compose.yml

# --- Pre-flight checks ---
echo "[check] Resolving ${container}..."
if getent hosts "${container}" >/dev/null 2>&1; then
  echo "[check] OK - ${container} resolves to $(getent hosts ${container} | awk '{print $1}')"
else
  echo "[check] FAIL - Cannot resolve ${container}. Is the Webots container running on droid-slam-network?"
  exit 1
fi

echo "[check] Testing port 5555 on ${container}..."
if timeout 3 bash -c "echo > /dev/tcp/${container}/5555" 2>/dev/null; then
  echo "[check] OK - port 5555 is reachable"
else
  echo "[check] WARN - port 5555 not reachable (Webots may not be publishing yet)"
  echo "[check]   -> Controller may have crashed. Check: docker logs drones_webots-sim"
fi

# Quick ZMQ frame test (5s timeout) - verify Webots is actually sending frames
echo "[check] Waiting for a test ZMQ frame (5s timeout)..."
if python3 -c "
import zmq, sys
ctx = zmq.Context()
s = ctx.socket(zmq.SUB)
s.setsockopt(zmq.RCVTIMEO, 5000)
s.setsockopt_string(zmq.SUBSCRIBE, '')
s.connect('tcp://${container}:5555')
try:
    parts = s.recv_multipart()
    print(f'[check] OK - received test frame: {len(parts)} part(s), {sum(len(p) for p in parts)} bytes')
except zmq.Again:
    print('[check] WARN - no frame received in 5s. Webots may not be sending.')
    print('[check]   -> Is the simulation running (not paused)?')
    print('[check]   -> Run ./scripts/test-zmq.sh for detailed diagnostics')
finally:
    s.close()
    ctx.term()
" 2>&1; then
  true
fi

echo "[check] Starting DROID-SLAM..."

# Run DROID-SLAM with ZMQ configuration as specified in ZMQ_INSTRUCTIONS.md
python demo.py \
  --zmq=tcp://${container}:5555 \
  --zmq_sender=tcp://*:5556 \
  --calib=calib/tartan.txt \
  --reconstruction_path=reconstructions/mesh.pth \
  --stride=1
# --disable_vis
