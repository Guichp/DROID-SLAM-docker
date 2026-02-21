import zmq
import numpy as np
import cv2
import torch
import time
import pickle
import threading

class ZMQImageReceiver:
    def __init__(self, zmq_addr, calib_file, stride=1):
        self.zmq_addr = zmq_addr
        self.stride = stride
        self.context = zmq.Context()
        self.socket = None
        self._connect()

        self.calib = np.loadtxt(calib_file, delimiter=" ")
        self.fx, self.fy, self.cx, self.cy = self.calib[:4]

        self.K = np.eye(3)
        self.K[0,0] = self.fx
        self.K[0,2] = self.cx
        self.K[1,1] = self.fy
        self.K[1,2] = self.cy

        self.running = True

        # Error recovery state
        self.consecutive_errors = 0
        self.retry_delay = 0.1  # Start with 100ms
        self.max_retry_delay = 5.0  # Max 5 seconds
        self.max_errors_before_reconnect = 10

        print(f"[ZMQ] Listening for images on {zmq_addr}...")

    def _connect(self):
        """Create and connect the ZMQ socket."""
        if self.socket is not None:
            try:
                self.socket.close()
            except:
                pass
        self.socket = self.context.socket(zmq.SUB)
        self.socket.setsockopt(zmq.RCVTIMEO, 1000)  # 1 second timeout
        self.socket.setsockopt_string(zmq.SUBSCRIBE, "")
        self.socket.connect(self.zmq_addr)

    def _reconnect(self):
        """Attempt to reconnect the ZMQ socket with backoff."""
        print(f"[ZMQ] Attempting reconnect to {self.zmq_addr}...")
        try:
            self._connect()
            print(f"[ZMQ] Reconnected successfully")
            self.consecutive_errors = 0
            self.retry_delay = 0.1
        except Exception as e:
            print(f"[ZMQ] Reconnect failed: {e}")
            time.sleep(self.retry_delay)
            self.retry_delay = min(self.retry_delay * 2, self.max_retry_delay)

    def stop(self):
        self.running = False
        if self.socket:
            self.socket.close()
        self.context.term()

    def __iter__(self):
        t = 0
        while self.running:
            try:
                # Non-blocking receive to allow checking self.running
                # Webots sends multipart messages: [metadata_json, jpeg_bytes]
                try:
                    parts = self.socket.recv_multipart(flags=zmq.NOBLOCK)
                    # Reset error state on successful receive
                    self.consecutive_errors = 0
                    self.retry_delay = 0.1
                except zmq.Again:
                    time.sleep(0.01)
                    continue

                # Handle multipart (metadata + image) or single-part messages
                if len(parts) >= 2:
                    # parts[0] = metadata JSON (frame_id, timestamp, etc.)
                    # parts[1] = JPEG image bytes
                    msg = parts[1]
                else:
                    # Fallback for single-part messages (raw image only)
                    msg = parts[0]

                buf = np.frombuffer(msg, dtype=np.uint8)
                image = cv2.imdecode(buf, cv2.IMREAD_COLOR)

                if image is None:
                    continue

                if len(self.calib) > 4:
                    image = cv2.undistort(image, self.K, self.calib[4:])

                h0, w0, _ = image.shape
                h1 = int(h0 * np.sqrt((384 * 512) / (h0 * w0)))
                w1 = int(w0 * np.sqrt((384 * 512) / (h0 * w0)))

                image = cv2.resize(image, (w1, h1))
                image = image[:h1-h1%8, :w1-w1%8]
                image = torch.as_tensor(image).permute(2, 0, 1)

                intrinsics = torch.as_tensor([self.fx, self.fy, self.cx, self.cy])
                intrinsics[0::2] *= (w1 / w0)
                intrinsics[1::2] *= (h1 / h0)

                yield t, image[None], intrinsics
                t += 1

            except KeyboardInterrupt:
                self.stop()
                break
            except zmq.ZMQError as e:
                self.consecutive_errors += 1
                print(f"[ZMQ] Error (attempt {self.consecutive_errors}): {e}")

                if self.consecutive_errors >= self.max_errors_before_reconnect:
                    self._reconnect()
                else:
                    time.sleep(self.retry_delay)
                    self.retry_delay = min(self.retry_delay * 2, self.max_retry_delay)
            except Exception as e:
                self.consecutive_errors += 1
                print(f"[ZMQ] Error receiving image (attempt {self.consecutive_errors}): {e}")

                if self.consecutive_errors >= self.max_errors_before_reconnect:
                    self._reconnect()
                else:
                    time.sleep(self.retry_delay)
                    self.retry_delay = min(self.retry_delay * 2, self.max_retry_delay)

class ZMQPointCloudSender:
    def __init__(self, zmq_addr):
        self.zmq_addr = zmq_addr
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.PUB)
        self.socket.bind(zmq_addr)
        print(f"Publishing point clouds to {zmq_addr}...")

    def send(self, droid_video):
        # Extract data from droid_video (DepthVideo object)
        # We need to be careful about synchronization if accessing shared memory
        # But for reading, it might be okay or we might get tearing.
        # Droid uses .cpu() which copies.
        
        with droid_video.get_lock():
            t = droid_video.counter.value
            # Clone to avoid modification during send preparation
            tstamps = droid_video.tstamp[:t].cpu().numpy()
            poses = droid_video.poses[:t].cpu().numpy()
            disps = droid_video.disps_up[:t].cpu().numpy()
            intrinsics = droid_video.intrinsics[:t].cpu().numpy()
            # Images might be too large to send every time? 
            # The user said "send each iteration of the point cloud".
            # Maybe we don't send images, just geometry?
            # "Every time the point cloud gets new points, they're sent to another service for evaluation."
            # Evaluation usually needs geometry.
            # I'll send images too just in case, but maybe compressed?
            # Sending raw images for every frame every update is huge.
            # But let's stick to the request.
            # images = droid_video.images[:t].cpu().numpy() 
        
        data = {
            "tstamps": tstamps,
            "poses": poses,
            "disps": disps,
            "intrinsics": intrinsics,
            # "images": images
        }
        
        # Serialize and send
        try:
            # Use pickle for simplicity, or custom binary format for speed
            msg = pickle.dumps(data)
            self.socket.send(msg)
        except Exception as e:
            print(f"Error sending point cloud: {e}")

