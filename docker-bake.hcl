variable "TAG" {
  default = "zyeesi"
}

variable "IMAGE_REPO" {
  default = "ghcr.io/zyeesi/zyeesi-zye-i2v-runpod-template"
}

# === Version Pins (single source of truth) ===
variable "COMFYUI_VERSION" {
  default = "v0.18.2"
}
variable "MANAGER_SHA" {
  default = "bbafbb1290f0"
}
variable "KJNODES_SHA" {
  default = "068d4fee62d3"
}
variable "CIVICOMFY_SHA" {
  default = "555e984bbcb0"
}

# Regular image (cu128)
variable "TORCH_VERSION" {
  default = "2.11.0+cu128"
}
variable "TORCHVISION_VERSION" {
  default = "0.26.0+cu128"
}
variable "TORCHAUDIO_VERSION" {
  default = "2.11.0+cu128"
}

# 5090 image (cu130) — can diverge from regular when needed
variable "FILEBROWSER_VERSION" {
  default = "v2.59.0"
}
variable "FILEBROWSER_SHA256" {
  default = "8cd8c3baecb086028111b912f252a6e3169737fa764b5c510139e81f9da87799"
}

group "default" {
  targets = ["common", "dev"]
}

# Common settings for all targets (defaults to regular CUDA 12.8 / cu128)
target "common" {
  context    = "."
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64"]
  args = {
    COMFYUI_VERSION     = COMFYUI_VERSION
    MANAGER_SHA         = MANAGER_SHA
    KJNODES_SHA         = KJNODES_SHA
    CIVICOMFY_SHA       = CIVICOMFY_SHA
    TORCH_VERSION       = TORCH_VERSION
    TORCHVISION_VERSION = TORCHVISION_VERSION
    TORCHAUDIO_VERSION  = TORCHAUDIO_VERSION
    FILEBROWSER_VERSION = FILEBROWSER_VERSION
    FILEBROWSER_SHA256  = FILEBROWSER_SHA256
    CUDA_VERSION_DASH   = "12-8"
    TORCH_INDEX_SUFFIX  = "cu128"
  }
}

# Regular ComfyUI image (CUDA 12.8 — default)
target "regular" {
  inherits = ["common"]
  tags = [
    "${IMAGE_REPO}:${TAG}-cuda12.8",
    "${IMAGE_REPO}:cuda12.8",
    "${IMAGE_REPO}:latest",
  ]
}

# Dev image for local testing
target "dev" {
  inherits = ["common"]
  tags = ["${IMAGE_REPO}:dev"]
  output = ["type=docker"]
}

# Dev push targets (for CI pushing dev tags, without overriding latest)
target "devpush" {
  inherits = ["common"]
  tags = [
    "${IMAGE_REPO}:${TAG}",
    "${IMAGE_REPO}:${TAG}-cuda12.8",
    "${IMAGE_REPO}:dev",
    "${IMAGE_REPO}:dev-cuda12.8",
  ]
}
