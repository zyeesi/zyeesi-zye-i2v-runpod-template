#!/bin/bash
set -e

COMFYUI_DIR="/workspace/ComfyUI"
VENV_DIR="$COMFYUI_DIR/.venv-cu128"
OLD_VENV_DIR="$COMFYUI_DIR/.venv"
FILEBROWSER_CONFIG="/root/.config/filebrowser/config.json"
DB_FILE="/workspace/filebrowser.db"
ARGS_FILE="/workspace/comfyui_args.txt"
BOOTSTRAP_LOG="/workspace/bootstrap_models.log"
COMFY_PID=""
BOOTSTRAP_PID=""

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                 #
# ---------------------------------------------------------------------------- #

setup_ssh() {
    mkdir -p ~/.ssh

    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        ssh-keygen -A -q
    fi

    if [[ $PUBLIC_KEY ]]; then
        echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh
    else
        RANDOM_PASS=$(openssl rand -base64 12)
        echo "root:${RANDOM_PASS}" | chpasswd
        echo "Generated random SSH password for root: ${RANDOM_PASS}"
    fi

    echo "PermitUserEnvironment yes" >> /etc/ssh/sshd_config
    /usr/sbin/sshd
}

export_env_vars() {
    echo "Exporting environment variables..."

    ENV_FILE="/etc/environment"
    PAM_ENV_FILE="/etc/security/pam_env.conf"
    SSH_ENV_DIR="/root/.ssh/environment"

    cp "$ENV_FILE" "${ENV_FILE}.bak" 2>/dev/null || true
    cp "$PAM_ENV_FILE" "${PAM_ENV_FILE}.bak" 2>/dev/null || true

    > "$ENV_FILE"
    > "$PAM_ENV_FILE"
    mkdir -p /root/.ssh
    > "$SSH_ENV_DIR"

    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH|^HF_|^HUGGINGFACE_|^TRANSFORMERS_CACHE|^CIVITAI_' | while read -r line; do
        name=$(echo "$line" | cut -d= -f1)
        value=$(echo "$line" | cut -d= -f2-)

        echo "$name=\"$value\"" >> "$ENV_FILE"
        echo "$name DEFAULT=\"$value\"" >> "$PAM_ENV_FILE"
        echo "$name=\"$value\"" >> "$SSH_ENV_DIR"
        echo "export $name=\"$value\"" >> /etc/rp_environment
    done

    echo 'source /etc/rp_environment' >> ~/.bashrc
    echo 'source /etc/rp_environment' >> /etc/bash.bashrc

    chmod 644 "$ENV_FILE" "$PAM_ENV_FILE"
    chmod 600 "$SSH_ENV_DIR"
}

start_jupyter() {
    mkdir -p /workspace
    echo "Starting Jupyter Lab on port 8888..."
    nohup jupyter lab \
        --allow-root \
        --no-browser \
        --port=8888 \
        --ip=0.0.0.0 \
        --FileContentsManager.delete_to_trash=False \
        --FileContentsManager.preferred_dir=/workspace \
        --ServerApp.root_dir=/workspace \
        --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
        --IdentityProvider.token="${JUPYTER_PASSWORD:-}" \
        --ServerApp.allow_origin=* &> /jupyter.log &
    echo "Jupyter Lab started"
}

prepare_model_dirs() {
    mkdir -p "$COMFYUI_DIR/models/checkpoints"
    mkdir -p "$COMFYUI_DIR/models/clip"
    mkdir -p "$COMFYUI_DIR/models/clip_vision"
    mkdir -p "$COMFYUI_DIR/models/configs"
    mkdir -p "$COMFYUI_DIR/models/controlnet"
    mkdir -p "$COMFYUI_DIR/models/vae"
    mkdir -p "$COMFYUI_DIR/models/loras"
    mkdir -p "$COMFYUI_DIR/models/embeddings"
    mkdir -p "$COMFYUI_DIR/models/text_encoders"
    mkdir -p "$COMFYUI_DIR/models/diffusion_models"
    mkdir -p "$COMFYUI_DIR/models/unet"
    mkdir -p "$COMFYUI_DIR/models/upscale_models"
    mkdir -p "$COMFYUI_DIR/models/rife"
    mkdir -p "$COMFYUI_DIR/models/LLM/cache"

    export HF_HOME="$COMFYUI_DIR/models/LLM/cache"
    export HUGGINGFACE_HUB_CACHE="$COMFYUI_DIR/models/LLM/cache"
    export TRANSFORMERS_CACHE="$COMFYUI_DIR/models/LLM/cache"
}

setup_rife_symlink() {
    if [ -d "$COMFYUI_DIR/custom_nodes/ComfyUI-Frame-Interpolation" ] && [ ! -e "$COMFYUI_DIR/custom_nodes/comfyui-frame-interpolation" ]; then
        ln -s "$COMFYUI_DIR/custom_nodes/ComfyUI-Frame-Interpolation" "$COMFYUI_DIR/custom_nodes/comfyui-frame-interpolation"
    fi

    rm -rf "$COMFYUI_DIR/custom_nodes/comfyui-frame-interpolation/ckpts" || true
    ln -sf "$COMFYUI_DIR/models/rife" "$COMFYUI_DIR/custom_nodes/comfyui-frame-interpolation/ckpts"
}

cleanup_children() {
    if [ -n "$BOOTSTRAP_PID" ]; then
        kill "$BOOTSTRAP_PID" 2>/dev/null || true
    fi

    if [ -n "$COMFY_PID" ]; then
        kill "$COMFY_PID" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                    #
# ---------------------------------------------------------------------------- #

setup_ssh
export_env_vars

if [ ! -f "$DB_FILE" ]; then
    echo "Initializing FileBrowser..."
    filebrowser config init
    filebrowser config set --address 0.0.0.0
    filebrowser config set --port 8080
    filebrowser config set --root /workspace
    filebrowser config set --auth.method=json
    filebrowser users add admin adminadmin12 --perm.admin
else
    echo "Using existing FileBrowser configuration..."
fi

echo "Starting FileBrowser on port 8080..."
nohup filebrowser &> /filebrowser.log &

start_jupyter

if [ ! -f "$ARGS_FILE" ]; then
    echo "# Add your custom ComfyUI arguments here (one per line)" > "$ARGS_FILE"
    echo "Created empty ComfyUI arguments file at $ARGS_FILE"
fi

if [ -d "$OLD_VENV_DIR" ] && [ ! -d "$VENV_DIR" ]; then
    NODE_COUNT=$(find "$COMFYUI_DIR/custom_nodes" -maxdepth 2 -name "requirements.txt" 2>/dev/null | wc -l)
    echo "============================================="
    echo "  CUDA 12.4 -> 12.8 migration"
    echo "  Reinstalling deps for $NODE_COUNT custom nodes"
    echo "  This may take several minutes"
    echo "============================================="
    mv "$OLD_VENV_DIR" "${OLD_VENV_DIR}.bak"
    cd "$COMFYUI_DIR"
    python3.12 -m venv --system-site-packages "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    python -m ensurepip
    BAKED_NODES="ComfyUI-Manager ComfyUI-KJNodes Civicomfy ComfyUI-QwenVL ComfyUI-PainterI2V comfyui-find-perfect-resolution ComfyUI-Easy-Use rgthree-comfy ComfyUI-Frame-Interpolation ComfyUI-VideoHelperSuite ComfyUI_essentials ComfyUI-HuggingFace"
    CURRENT=0
    INSTALLED=0
    for req in "$COMFYUI_DIR"/custom_nodes/*/requirements.txt; do
        if [ -f "$req" ]; then
            NODE_NAME=$(basename "$(dirname "$req")")
            case " $BAKED_NODES " in
                *" $NODE_NAME "*) continue ;;
            esac
            CURRENT=$((CURRENT + 1))
            echo "[$CURRENT] $NODE_NAME"
            pip install -r "$req" 2>&1 | grep -E "^(Successfully|ERROR)" || true
            INSTALLED=$((INSTALLED + 1))
        fi
    done
    echo "Upgrading ComfyUI requirements..."
    pip install --upgrade -r "$COMFYUI_DIR/requirements.txt" 2>&1 | grep -E "^(Successfully|ERROR)" || true
    echo "Migration complete - $INSTALLED user nodes processed (${NODE_COUNT} total, baked nodes skipped)"
    echo "Old venv backed up at ${OLD_VENV_DIR}.bak - delete it to free space:"
    echo "  rm -rf ${OLD_VENV_DIR}.bak"
fi

if [ ! -d "$COMFYUI_DIR" ] || [ ! -d "$VENV_DIR" ]; then
    echo "First time setup: Copying baked ComfyUI to workspace..."

    if [ ! -d "$COMFYUI_DIR" ]; then
        cp -r /opt/comfyui-baked "$COMFYUI_DIR"
        echo "ComfyUI copied to workspace"
    fi

    if [ ! -d "$VENV_DIR" ]; then
        cd "$COMFYUI_DIR"
        python3.12 -m venv --system-site-packages "$VENV_DIR"
        source "$VENV_DIR/bin/activate"
        python -m ensurepip
        echo "Base packages (torch, numpy, etc.) available from system site-packages"
        echo "ComfyUI ready - all dependencies pre-installed in image"
    fi
else
    source "$VENV_DIR/bin/activate"
    echo "Using existing ComfyUI installation"
fi

prepare_model_dirs
setup_rife_symlink

python -m pip --version > /dev/null 2>&1

cd "$COMFYUI_DIR"
FIXED_ARGS="--listen 0.0.0.0 --port 8188 --enable-cors-header"
if [ -s "$ARGS_FILE" ]; then
    CUSTOM_ARGS=$(grep -v '^#' "$ARGS_FILE" | tr '\n' ' ')
    if [ ! -z "$CUSTOM_ARGS" ]; then
        FIXED_ARGS="$FIXED_ARGS $CUSTOM_ARGS"
    fi
fi

echo "Starting ComfyUI with args: $FIXED_ARGS"
python main.py $FIXED_ARGS &
COMFY_PID=$!

if [ -f "$COMFYUI_DIR/bootstrap_models.py" ]; then
    echo "Starting model bootstrap in background..."
    echo "Bootstrap logs: $BOOTSTRAP_LOG"
    : > "$BOOTSTRAP_LOG"
    python "$COMFYUI_DIR/bootstrap_models.py" \
        > >(tee -a "$BOOTSTRAP_LOG") \
        2> >(tee -a "$BOOTSTRAP_LOG" >&2) &
    BOOTSTRAP_PID=$!
fi

trap cleanup_children SIGTERM SIGINT
wait $COMFY_PID || true

echo "============================================="
echo "  ComfyUI crashed - check the logs above."
echo "  SSH and JupyterLab are still available."
echo "  To restart after fixing:"
echo "    cd $COMFYUI_DIR && source .venv-cu128/bin/activate"
echo "    python main.py $FIXED_ARGS"
echo "============================================="

sleep infinity
