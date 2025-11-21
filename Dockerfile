# Use NVIDIA CUDA base image with development tools
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set CUDA archs explicitly to avoid build-time auto-detection (no GPU in build env)
ENV TORCH_CUDA_ARCH_LIST="6.0;6.1;7.0;7.5;8.0;8.6"

# Set working directory
WORKDIR /workspace

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Build essentials
    build-essential \
    cmake \
    git \
    wget \
    curl \
    unzip \
    # Python
    python3.11 \
    python3.11-dev \
    python3-pip \
    python3.11-distutils \
    # Build helper (ninja)
    ninja-build \
    # VNC and Desktop
    tigervnc-standalone-server \
    tigervnc-common \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    # noVNC dependencies
    net-tools \
    novnc \
    websockify \
    # Graphics libraries
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    # Other utilities
    nano \
    vim \
    htop \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create symbolic link for python
RUN ln -sf /usr/bin/python3.10 /usr/bin/python

# Upgrade pip
RUN python -m pip install --upgrade pip wheel && \
    # pin packaging to avoid canonicalize_version signature mismatch during metadata generation
    python -m pip install "packaging<24" "setuptools<68"

# Install PyTorch with CUDA 12.8 support
# Adjust version based on your needs - check https://pytorch.org/get-started/locally/
RUN pip install torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu128

# Install DROID-SLAM Python dependencies
RUN pip install \
    numpy \
    opencv-python \
    matplotlib \
    scipy \
    tqdm \
    evo \
    gdown

# Optional visualization dependencies
RUN pip install moderngl moderngl-window || true

# Clone DROID-SLAM repository
RUN git clone --recursive https://github.com/princeton-vl/DROID-SLAM.git /workspace/DROID-SLAM

# Set DROID-SLAM as working directory
WORKDIR /workspace/DROID-SLAM

# Install DROID-SLAM third-party dependencies
# lietorch
RUN pip install --no-build-isolation thirdparty/lietorch
# the --no-build-isolation flag is recommended because it requires
# direct access to Pytorch CUDA config during compilation

# pytorch_scatter (this may take a while)
RUN pip install thirdparty/pytorch_scatter

# Install DROID-SLAM backends
RUN pip install --no-build-isolation .
# RUN pip install --no-build-isolation -e .

# Download pretrained model
RUN bash tools/download_model.sh

# Set up VNC
RUN mkdir -p /root/.vnc && \
    echo "password" | vncpasswd -f > /root/.vnc/passwd && \
    chmod 600 /root/.vnc/passwd

# Create VNC startup script
RUN echo '#!/bin/bash\n\
[ -f $HOME/.Xresources ] && xrdb $HOME/.Xresources\n\
startxfce4 &' > /root/.vnc/xstartup && \
    chmod +x /root/.vnc/xstartup

# Set up noVNC
RUN ln -s /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# Create startup script
RUN echo '#!/bin/bash\n\
# Start VNC server\n\
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no\n\
\n\
# Start noVNC\n\
websockify -D --web=/usr/share/novnc/ 6080 localhost:5901\n\
\n\
# Keep container running\n\
tail -f /dev/null' > /root/start.sh && \
    chmod +x /root/start.sh

# Expose VNC and noVNC ports
EXPOSE 5901 6080

# Environment variables
ENV DISPLAY=:1 \
    VNC_RESOLUTION=1920x1080 \
    VNC_DEPTH=24

# Set entrypoint
CMD ["/root/start.sh"]
