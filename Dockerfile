# ============================================================================
# Stage 1: Builder - Download pinned sources and install all Python packages
# ============================================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# ---- Version pins (set in docker-bake.hcl) ----
ARG COMFYUI_VERSION
ARG MANAGER_SHA
ARG KJNODES_SHA
ARG CIVICOMFY_SHA
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION

# ---- CUDA variant (set in docker-bake.hcl per target) ----
ARG CUDA_VERSION_DASH=12-8
ARG TORCH_INDEX_SUFFIX=cu128

# Install minimal dependencies needed for building
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    curl \
    git \
    ca-certificates \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    build-essential \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} libcusparse-dev-${CUDA_VERSION_DASH} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm cuda-keyring_1.1-1_all.deb \
    && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Install pip and pip-tools for lock file generation
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.12 get-pip.py && \
    python3.12 -m pip install --no-cache-dir pip-tools && \
    rm get-pip.py

# Set CUDA environment for building
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# Download pinned source archives
WORKDIR /tmp/build
RUN curl -fSL "https://github.com/comfyanonymous/ComfyUI/archive/refs/tags/${COMFYUI_VERSION}.tar.gz" -o comfyui.tar.gz && \
    mkdir -p ComfyUI && tar xzf comfyui.tar.gz --strip-components=1 -C ComfyUI && rm comfyui.tar.gz

WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN curl -fSL "https://github.com/ltdrdata/ComfyUI-Manager/archive/${MANAGER_SHA}.tar.gz" -o manager.tar.gz && \
    mkdir -p ComfyUI-Manager && tar xzf manager.tar.gz --strip-components=1 -C ComfyUI-Manager && rm manager.tar.gz && \
    curl -fSL "https://github.com/kijai/ComfyUI-KJNodes/archive/${KJNODES_SHA}.tar.gz" -o kjnodes.tar.gz && \
    mkdir -p ComfyUI-KJNodes && tar xzf kjnodes.tar.gz --strip-components=1 -C ComfyUI-KJNodes && rm kjnodes.tar.gz && \
    curl -fSL "https://github.com/MoonGoblinDev/Civicomfy/archive/${CIVICOMFY_SHA}.tar.gz" -o civicomfy.tar.gz && \
    mkdir -p Civicomfy && tar xzf civicomfy.tar.gz --strip-components=1 -C Civicomfy && rm civicomfy.tar.gz

# Add your extra custom nodes on top of the base template nodes
RUN git clone --depth 1 https://github.com/1038lab/ComfyUI-QwenVL.git && \
    git clone --depth 1 https://github.com/princepainter/ComfyUI-PainterI2V.git && \
    git clone --depth 1 https://github.com/ashtar1984/comfyui-find-perfect-resolution.git && \
    git clone --depth 1 https://github.com/yolain/ComfyUI-Easy-Use.git && \
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth 1 https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone --depth 1 https://github.com/cubiq/ComfyUI_essentials.git && \
    git clone --depth 1 https://github.com/huchukato/ComfyUI-HuggingFace.git

# Overlay project-specific ComfyUI config files onto the baked tree
COPY hf_models.json /tmp/build/ComfyUI/custom_nodes/ComfyUI-QwenVL/hf_models.json
COPY extra_model_paths.yaml /tmp/build/ComfyUI/extra_model_paths.yaml
COPY bootstrap_models.py /tmp/build/ComfyUI/bootstrap_models.py
COPY model_manifest.json /tmp/build/ComfyUI/model_manifest.json

# Init git repos with upstream remotes so ComfyUI-Manager can detect versions
# and users can update via Manager at their own risk
RUN cd /tmp/build/ComfyUI && \
    git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI ${COMFYUI_VERSION}" && git tag "${COMFYUI_VERSION}" && \
    git remote add origin https://github.com/comfyanonymous/ComfyUI.git && \
    cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-Manager && \
    git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-Manager ${MANAGER_SHA}" && \
    git remote add origin https://github.com/ltdrdata/ComfyUI-Manager.git && \
    cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-KJNodes && \
    git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-KJNodes ${KJNODES_SHA}" && \
    git remote add origin https://github.com/kijai/ComfyUI-KJNodes.git && \
    cd /tmp/build/ComfyUI/custom_nodes/Civicomfy && \
    git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "Civicomfy ${CIVICOMFY_SHA}" && \
    git remote add origin https://github.com/MoonGoblinDev/Civicomfy.git && \
    cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-QwenVL && \
    git add hf_models.json && \
    git -c user.name=- -c user.email=- commit -q -m "Configure ComfyUI-QwenVL models"

# Install Python requirements with torch pinned via constraints.
# Custom node requirements are installed one-by-one because aggregating them
# into a single resolver run is fragile and produces poor diagnostics.
WORKDIR /tmp/build
RUN cp ComfyUI/requirements.txt base-requirements.txt && \
    cat <<'EOF' >> base-requirements.txt
GitPython
opencv-python
jupyter
jupyter-resource-usage
jupyterlab-nvdashboard
transformers>=4.57.0
accelerate
diffusers
peft
bitsandbytes
huggingface_hub
hf_xet
einops
kornia
safetensors
scipy
omegaconf
opencv-contrib-python-headless
imageio-ffmpeg
numba
spandrel
sentencepiece
lark
colour-science
pixeloe
psutil
EOF
RUN \
    echo "torch==${TORCH_VERSION}" >> constraints.txt && \
    echo "torchvision==${TORCHVISION_VERSION}" >> constraints.txt && \
    echo "torchaudio==${TORCHAUDIO_VERSION}" >> constraints.txt && \
    echo "pillow>=12.1.1" >> constraints.txt && \
    TORCH_INDEX_URL="https://download.pytorch.org/whl/${TORCH_INDEX_SUFFIX}" && \
    python3.12 -m pip install --no-cache-dir --upgrade pip setuptools wheel && \
    python3.12 -m pip install --no-cache-dir --ignore-installed \
    --index-url https://pypi.org/simple \
    --extra-index-url "${TORCH_INDEX_URL}" \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    "torchaudio==${TORCHAUDIO_VERSION}" && \
    python3.12 -m pip install --no-cache-dir --ignore-installed \
    --constraint constraints.txt \
    --index-url https://pypi.org/simple \
    --extra-index-url "${TORCH_INDEX_URL}" \
    -r base-requirements.txt && \
    for req in ComfyUI/custom_nodes/*/requirements.txt; do \
        if [ -f "$req" ]; then \
            echo "Installing custom node requirements from $req"; \
            python3.12 -m pip install --no-cache-dir --ignore-installed \
            --constraint constraints.txt \
            --index-url https://pypi.org/simple \
            --extra-index-url "${TORCH_INDEX_URL}" \
            -r "$req"; \
        fi; \
    done

# Bake in SageAttention wheel
COPY wheels/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl /tmp/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl
RUN python3.12 -m pip install --no-cache-dir --no-deps /tmp/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl

# Pre-populate ComfyUI-Manager cache so first cold start skips the slow registry fetch
COPY scripts/prebake-manager-cache.py /tmp/prebake-manager-cache.py
RUN python3.12 /tmp/prebake-manager-cache.py /tmp/build/ComfyUI/user/__manager/cache

# Bake ComfyUI + custom nodes into a known location for runtime copy
RUN cp -r /tmp/build/ComfyUI /opt/comfyui-baked

# ============================================================================
# Stage 2: Runtime - Clean image with pre-installed packages
# ============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
ENV FILEBROWSER_CONFIG=/workspace/.filebrowser.json
ENV HF_HOME=/workspace/ComfyUI/models/LLM/cache
ENV HUGGINGFACE_HUB_CACHE=/workspace/ComfyUI/models/LLM/cache
ENV TRANSFORMERS_CACHE=/workspace/ComfyUI/models/LLM/cache

# ---- CUDA variant (re-declared for runtime stage) ----
ARG CUDA_VERSION_DASH=12-8

# ---- FileBrowser version pin (set in docker-bake.hcl) ----
ARG FILEBROWSER_VERSION
ARG FILEBROWSER_SHA256

# Update and install runtime dependencies, CUDA, and common tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    build-essential \
    libssl-dev \
    wget \
    gnupg \
    xz-utils \
    openssh-client \
    openssh-server \
    nano \
    curl \
    htop \
    tmux \
    ca-certificates \
    less \
    net-tools \
    iputils-ping \
    procps \
    openssl \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm cuda-keyring_1.1-1_all.deb \
    && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Copy Python packages, executables, and Jupyter data from builder stage
COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /usr/local/share/jupyter /usr/local/share/jupyter

# Register Jupyter extensions (pip --ignore-installed skips post-install hooks)
RUN mkdir -p /usr/local/etc/jupyter/jupyter_server_config.d && \
    echo '{"ServerApp":{"jpserver_extensions":{"jupyter_server_terminals":true,"jupyterlab":true,"jupyter_resource_usage":true,"jupyterlab_nvdashboard":true}}}' \
    > /usr/local/etc/jupyter/jupyter_server_config.d/extensions.json

# Copy baked ComfyUI + custom nodes from builder stage
COPY --from=builder /opt/comfyui-baked /opt/comfyui-baked
COPY scripts/healthcheck.py /usr/local/bin/healthcheck.py

# Remove uv to force ComfyUI-Manager to use pip (uv doesn't respect --system-site-packages properly)
RUN pip uninstall -y uv 2>/dev/null || true && \
    rm -f /usr/local/bin/uv /usr/local/bin/uvx && \
    chmod +x /usr/local/bin/healthcheck.py

# Install FileBrowser (pinned version with checksum)
RUN curl -fSL "https://github.com/filebrowser/filebrowser/releases/download/${FILEBROWSER_VERSION}/linux-amd64-filebrowser.tar.gz" -o /tmp/fb.tar.gz && \
    echo "${FILEBROWSER_SHA256}  /tmp/fb.tar.gz" | sha256sum -c - && \
    tar xzf /tmp/fb.tar.gz -C /usr/local/bin filebrowser && \
    rm /tmp/fb.tar.gz

# Set CUDA environment variables
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# Allow container to start on hosts with older CUDA 12.x drivers
ENV NVIDIA_REQUIRE_CUDA=""
ENV NVIDIA_DISABLE_REQUIRE=true
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

# Configure SSH for root login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd && \
    rm -f /etc/ssh/ssh_host_*

# Create workspace directory
RUN mkdir -p /workspace
WORKDIR /workspace

# Expose ports
EXPOSE 8188 22 8888 8080

# Copy start script
COPY start.sh /start.sh

# Set Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --set python3 /usr/bin/python3.12

HEALTHCHECK --interval=30s --timeout=30s --start-period=240s --retries=10 CMD ["python3", "/usr/local/bin/healthcheck.py"]

ENTRYPOINT ["/start.sh"]
