# DROID-SLAM ZMQ Interface Instructions

This modified version of DROID-SLAM supports receiving images via ZeroMQ (ZMQ) and sending the reconstruction point cloud to a remote system via ZMQ.

## Usage

To run DROID-SLAM with ZMQ interfaces, use the `demo.py` script with the following arguments:

### Arguments

- `--zmq=<address>`: The ZMQ address to subscribe to for receiving images.
  - Example: `tcp://localhost:5555` (Connects to a publisher at this address)
  - The expected image format is a byte buffer of an encoded image (e.g., JPEG, PNG) that can be decoded with `cv2.imdecode`.

- `--zmq_sender=<address>`: The ZMQ address to bind to for publishing point cloud updates.
  - Example: `tcp://*:5556` (Binds to port 5556 on all interfaces)
  - The system publishes a pickled dictionary containing the reconstruction state after each iteration.

- `--calib=<path>`: Path to the camera calibration file (required).

### Example Command

```bash
python demo.py --zmq=tcp://127.0.0.1:5555 --zmq_sender=tcp://*:5556 --calib=calib/tartan.txt --stride=1
```

There is a bash script in the `scripts/` folder to automate running with the desired parameters.

## Output Data Format

The data sent via `--zmq_sender` is a Python dictionary serialized with `pickle`. It contains the following keys:

- `tstamps`: Timestamps of the keyframes.
- `poses`: Camera poses (SE3) for the keyframes.
- `disps`: Inverse depth maps (disparities) for the keyframes.
- `intrinsics`: Camera intrinsics.

## Stopping

The execution will run indefinitely waiting for images. To stop the process:

- Press `Ctrl+C` in the terminal.
- Press `Q` in the visualization window (if visualization is enabled).
