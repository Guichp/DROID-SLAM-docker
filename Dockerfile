FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu22.04

# Set non-interactive mode for apt and install basic dependencies
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
software-properties-common build-essential wget curl git ca-certificates && \
add-apt-repository ppa:deadsnakes/ppa && apt-get update && \
apt-get install -y --no-install-recommends python3.11 python3.11-dev python3.11-distutils && \
apt-get install -y xfce4 xfce4-goodies tightvncserver && \
apt-get clean && rm -rf /var/lib/apt/lists/*
#xfce4 xfce4-goodies tightvncserver for vnc server 

# Install pip for Python 3.11
RUN wget https://bootstrap.pypa.io/get-pip.py && python3.11 get-pip.py && rm get-pip.py

# Install PyTorch, Torchvision, Torchaudio with CUDA support, and Transformers
ENV TORCH_VERSION=2.7.0
ENV CUDA_VERSION=12.8
# PyTorch 2.7.0 provides cu124 wheels which run fine on the CUDA 12.8 base runtime.
ENV PYTORCH_CHANNEL=https://download.pytorch.org/whl/cu128
RUN python3.11 -m pip install --no-cache-dir --index-url ${PYTORCH_CHANNEL} \
	torch==${TORCH_VERSION} torchvision==0.22.0 torchaudio==2.7.0 && \
    pip install websockify
    # websockify is for VNC server     
    
# Set Python3.11 as the default python
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# Create a workspace directory (for persistent volume mount) and set it as working dir
RUN mkdir /workspace
WORKDIR /workspace

# VNC server 
# copy the script into the container
COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

# set the entrypoint
ENTRYPOINT [ "/usr/local/bin/startup.sh" ]
EXPOSE 5901 6080

# Default command to keep container alive (so we can exec into it or run commands)
CMD [ "sleep", "infinity" ]