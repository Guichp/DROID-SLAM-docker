# Use NVIDIA CUDA base image with development tools (CUDA 11.3 to match torch build)
FROM nvidia/cuda:11.3.1-cudnn8-devel-ubuntu20.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set CUDA archs explicitly to avoid build-time auto-detection (no GPU in build env)
ENV TORCH_CUDA_ARCH_LIST="6.0;6.1;7.0;7.5;8.0;8.6"

# Set working directory
WORKDIR /workspace

# Install system dependencies
RUN apt-get update && apt-get install -y \
    software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y \
    # Build essentials
    build-essential \
    cmake \
    git \
    wget \
    curl \
    unzip \
    # Python 3.9 toolchain (matches Torch + CUDA combo)
    python3.9 \
    python3.9-dev \
    python3.9-distutils \
    python3.9-venv \
    python3-pip \
    # Build helper (ninja)
    ninja-build \
    # VNC and Desktop
    tightvncserver \
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
RUN ln -sf /usr/bin/python3.9 /usr/bin/python

# Bootstrap and upgrade pip for Python 3.9
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py && \
    python3.9 /tmp/get-pip.py && \
    rm /tmp/get-pip.py && \
    python -m pip install --upgrade pip wheel && \
    # pin packaging to avoid canonicalize_version signature mismatch during metadata generation
    python -m pip install "packaging<24" "setuptools<68"

# Install PyTorch with CUDA 11.3 support (matches DROID-SLAM requirements)
# Adjust version based on your needs - check https://pytorch.org/get-started/locally/
RUN python -m pip install \
    torch==1.10.0+cu113 \
    torchvision==0.11.1+cu113 \
    --extra-index-url https://download.pytorch.org/whl/cu113

# Install DROID-SLAM Python dependencies
RUN python -m pip install \
    numpy \
    opencv-python \
    matplotlib \
    scipy \
    tqdm \
    evo \
    gdown

# Optional visualization dependencies
RUN python -m pip install moderngl moderngl-window || true

# Clone DROID-SLAM repository
RUN git clone --recursive https://github.com/princeton-vl/DROID-SLAM.git /workspace/DROID-SLAM

# Set DROID-SLAM as working directory
WORKDIR /workspace/DROID-SLAM

# Install DROID-SLAM third-party dependencies
# lietorch
RUN python -m pip install --no-build-isolation thirdparty/lietorch
# the --no-build-isolation flag is recommended because it requires
# direct access to Pytorch CUDA config during compilation

# pytorch_scatter (this may take a while)
RUN python -m pip install thirdparty/pytorch_scatter

# Install DROID-SLAM backends
RUN python -m pip install --no-build-isolation .
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

# Copy startup script (legacy VNC/noVNC entrypoint)
COPY startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

# Expose VNC and noVNC ports
EXPOSE 5901 6080

# Set entrypoint and default command
ENTRYPOINT ["/usr/local/bin/startup.sh"]
CMD ["sleep", "infinity"]
