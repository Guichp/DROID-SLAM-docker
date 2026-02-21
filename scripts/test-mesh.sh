#!/bin/bash

# Mesh increment capture for DROID-SLAM → Autopilot
# Receives mesh increments for 30 seconds and saves the result as a .pth file
# compatible with view_reconstruction.py.
#
# Usage: ./scripts/test-mesh.sh [address] [duration_seconds]
#   Default address:  tcp://localhost:5556
#   Default duration: 30
#
# Output: reconstructions/mesh_capture_<timestamp>.pth
#   View with: python view_reconstruction.py reconstructions/mesh_capture_<timestamp>.pth

ADDR="${1:-tcp://localhost:5556}"
DURATION="${2:-30}"

# Extract host and port for the TCP check
HOST=$(echo "$ADDR" | sed -E 's|tcp://([^:]+):([0-9]+)|\1|')
PORT=$(echo "$ADDR" | sed -E 's|tcp://([^:]+):([0-9]+)|\2|')

echo "=== Mesh Increment Capture ==="
echo "Target:   $ADDR"
echo "Duration: ${DURATION}s"
echo ""

# 1. TCP port check
echo -n "[1/2] TCP port $PORT on $HOST: "
if timeout 3 bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
  echo "OK - port reachable"
else
  echo "FAIL - port not reachable"
  echo ""
  echo "  Cause: ZMQ PUB socket not bound — demo.py not running or --zmq_sender not passed"
  echo "  Fix:   Run ./scripts/droid-slam.sh first (it passes --zmq_sender=tcp://*:5556)"
  echo "  Check: ps aux | grep demo.py"
  exit 1
fi

# Ensure output directory exists
mkdir -p reconstructions

# 2. Receive mesh increments for DURATION seconds, save to .pth
echo "[2/2] Capturing mesh increments for ${DURATION}s..."
echo ""

python3 -c "
import zmq, sys, pickle, time, os
import numpy as np
import torch

ADDR = '$ADDR'
DURATION = $DURATION
OUT_DIR = 'reconstructions'

ctx = zmq.Context()
s = ctx.socket(zmq.SUB)
s.setsockopt(zmq.RCVTIMEO, 2000)   # 2s poll timeout
s.setsockopt_string(zmq.SUBSCRIBE, '')
s.connect(ADDR)

msg_count = 0
total_bytes = 0
latest_data = None
first_kf = None
start = time.time()

try:
    while time.time() - start < DURATION:
        remaining = DURATION - (time.time() - start)
        try:
            msg = s.recv()
        except zmq.Again:
            elapsed = time.time() - start
            if msg_count == 0:
                print(f'\r  Waiting for first message... ({elapsed:.0f}/{DURATION}s)', end='', flush=True)
            else:
                print(f'\r  Messages: {msg_count} | Keyframes: {latest_data[\"tstamps\"].shape[0]} | {elapsed:.0f}/{DURATION}s  ', end='', flush=True)
            continue

        data = pickle.loads(msg)
        msg_count += 1
        total_bytes += len(msg)
        latest_data = data

        n_kf = data['tstamps'].shape[0]
        if first_kf is None:
            first_kf = n_kf

        elapsed = time.time() - start
        print(f'\r  Messages: {msg_count} | Keyframes: {n_kf} | Bytes: {total_bytes:,} | {elapsed:.0f}/{DURATION}s  ', end='', flush=True)

except KeyboardInterrupt:
    print('\n  Interrupted by user.')
finally:
    s.close()
    ctx.term()

print()
print()

if latest_data is None:
    print('FAIL - no messages received in ${DURATION}s')
    print()
    print('  Cause: Publisher bound but not sending — no frames processed yet')
    print('  Fix:   Check that Webots is sending frames: ./scripts/test-zmq.sh')
    sys.exit(1)

# Print summary
print('=== Capture Summary ===')
print(f'  Messages received: {msg_count}')
print(f'  Total data:        {total_bytes:,} bytes')
print(f'  Keyframes:         {first_kf} -> {latest_data[\"tstamps\"].shape[0]}  (+{latest_data[\"tstamps\"].shape[0] - first_kf} during capture)')
print()
print('  Data shapes (latest snapshot):')
for key in sorted(latest_data.keys()):
    val = latest_data[key]
    if hasattr(val, 'shape'):
        print(f'    {key:12s}  {str(val.shape):20s}  dtype={val.dtype}')
    else:
        print(f'    {key:12s}  {val}')
print()

# Save as .pth (torch format) compatible with view_reconstruction.py
# view_reconstruction.py expects torch tensors with keys: images, disps, poses, intrinsics, tstamps
# The ZMQ publisher doesn't send images, so we create a dummy placeholder.
ts = latest_data['tstamps']
ps = latest_data['poses']
ds = latest_data['disps']
ins = latest_data['intrinsics']

save_data = {
    'tstamps':    torch.from_numpy(ts),
    'poses':      torch.from_numpy(ps),
    'disps':      torch.from_numpy(ds),
    'intrinsics': torch.from_numpy(ins),
}

# Generate output filename
timestamp = time.strftime('%Y%m%d_%H%M%S')
out_path = os.path.join(OUT_DIR, f'mesh_capture_{timestamp}.pth')

torch.save(save_data, out_path)

print(f'Saved: {out_path}')
print()
print('Note: This file contains poses, disparities, and intrinsics but no images.')
print('      view_reconstruction.py requires images — use for data inspection with torch.load() instead:')
print()
print(f'  python3 -c \"import torch; d=torch.load(\\'{out_path}\\'); [print(k, v.shape) for k,v in d.items()]\"')
"
