[![Watch the video](https://i3.ytimg.com/vi/JovhfHhxqdM/hqdefault.jpg)](https://www.youtube.com/watch?v=JovhfHhxqdM)

Run the i2v ComfyUI stack with dependencies baked into the image. On first boot, ComfyUI is copied to your workspace. The container health check only turns healthy after ComfyUI is responding and the required custom nodes have loaded.

## Access

- `8188`: ComfyUI web UI
- `8080`: FileBrowser (admin / adminadmin12)
- `8888`: JupyterLab (token via `JUPYTER_PASSWORD`, root at `/workspace`)
- `22`: SSH (set `PUBLIC_KEY` or check logs for generated root password)

## Pre-installed custom nodes

- ComfyUI-Manager
- ComfyUI-KJNodes
- Civicomfy
- ComfyUI-QwenVL
- ComfyUI-PainterI2V
- comfyui-find-perfect-resolution
- ComfyUI-Easy-Use
- rgthree-comfy
- ComfyUI-Frame-Interpolation
- ComfyUI-VideoHelperSuite
- ComfyUI_essentials
- ComfyUI-HuggingFace

## Published Image

GitHub Actions publishes to GitHub Container Registry at:

`ghcr.io/zyeesi/zyeesi-zye-i2v-runpod-template`

You can override that by setting a repository variable named `IMAGE_REPO`.
If you want RunPod to pull the image without registry credentials, make the published GHCR package public.

## Custom Arguments

Edit `/workspace/comfyui_args.txt` (one arg per line):

```text
--max-batch-size 8
--preview-method auto
```

## Directory Structure

- `/workspace/ComfyUI`: ComfyUI install
- `/workspace/comfyui_args.txt`: ComfyUI args
- `/workspace/filebrowser.db`: FileBrowser DB
- `/workspace/ComfyUI/models`: runtime model store

## Model Bootstrap

- On container start, `bootstrap_models.py` downloads the models declared in [model_manifest.json](/D:/Repo/zye-i2v-runpod-template/model_manifest.json)
- Set `HF_TOKEN` for Hugging Face downloads and `CIVITAI_API_KEY` for CivitAI downloads
- To add more checkpoints, LoRAs, or other assets, edit [model_manifest.json](/D:/Repo/zye-i2v-runpod-template/model_manifest.json)
- Detailed format and examples are in [docs/models.md](/D:/Repo/zye-i2v-runpod-template/docs/models.md)

## GitHub Actions

- Push to `main` to publish dev images: `:dev`, `:dev-cuda12.8`, and `:dev-cuda13.0`
- Push a `v*` tag to publish release images and update `:latest`
- For RunPod, point your template at `ghcr.io/zyeesi/zyeesi-zye-i2v-runpod-template:latest` or a versioned release tag like `ghcr.io/zyeesi/zyeesi-zye-i2v-runpod-template:v0.1.0-cuda12.8`
