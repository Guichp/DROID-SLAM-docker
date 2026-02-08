#!/bin/bash

# ZMQ connectivity diagnostic for DROID-SLAM ↔ Webots
# Run this inside the DROID-SLAM container to isolate frame delivery issues.

container="drones_webots-sim"

echo "=== ZMQ Connectivity Test ==="

# 1. DNS resolution
echo -n "[1/3] DNS resolution: "
if getent hosts "$container" > /dev/null 2>&1; then
  echo "OK - $(getent hosts "$container" | awk '{print $1}')"
else
  echo "FAIL - cannot resolve $container"
  echo "  -> Are both containers on droid-slam-network?"
  echo "  -> Check: docker network inspect droid-slam-network"
  exit 1
fi

# 2. TCP port check
echo -n "[2/3] TCP port 5555: "
if timeout 3 bash -c "echo > /dev/tcp/$container/5555" 2>/dev/null; then
  echo "OK - port reachable"
else
  echo "FAIL - port not reachable"
  echo "  -> Webots ZMQ socket not bound. Controller may have crashed."
  echo "  -> Check: docker logs drones_webots-sim"
  exit 1
fi

# 3. ZMQ frame reception (wait up to 10 seconds for one frame)
echo "[3/3] Waiting for a ZMQ frame (10s timeout)..."
python3 -c "
import zmq, sys

ctx = zmq.Context()
s = ctx.socket(zmq.SUB)
s.setsockopt(zmq.RCVTIMEO, 10000)
s.setsockopt_string(zmq.SUBSCRIBE, '')
s.connect('tcp://${container}:5555')
try:
    parts = s.recv_multipart()
    print(f'OK - received {len(parts)} part(s), total {sum(len(p) for p in parts)} bytes')
    if len(parts) >= 2:
        import json
        try:
            meta = json.loads(parts[0])
            print(f'  Metadata: {meta}')
            print(f'  Image size: {len(parts[1])} bytes')
        except Exception:
            print(f'  Part 0: {len(parts[0])} bytes (not JSON)')
            print(f'  Part 1: {len(parts[1])} bytes')
except zmq.Again:
    print('FAIL - no message received in 10 seconds')
    print('  -> Webots may not be sending frames.')
    print('  -> Check: docker logs drones_webots-sim')
    print('  -> Is the simulation running (not paused)?')
    sys.exit(1)
finally:
    s.close()
    ctx.term()
"
