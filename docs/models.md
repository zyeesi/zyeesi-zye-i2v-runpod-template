# Model Bootstrap

This template bootstraps runtime models from [model_manifest.json](/D:/Repo/zye-i2v-runpod-template/model_manifest.json) after ComfyUI starts.

## Current behavior

- Models download into `/workspace/ComfyUI/models`
- Existing files are skipped
- Hugging Face snapshots download into the HF cache under `/workspace/ComfyUI/models/LLM/cache`
- Bootstrap runs in the background, so ComfyUI can become available before all model downloads finish
- Bootstrap logs are written to `/workspace/bootstrap_models.log` and also appear in the container logs
- RIFE weights are not pre-downloaded here; the node can still fetch them on first use

## Required environment variables

- `HF_TOKEN`
  Use for private or gated Hugging Face repos. Public repos may still work without it.
- `CIVITAI_API_KEY`
  Required for the CivitAI version downloads in the current manifest.

## Manifest format

Each entry in `model_manifest.json` has a `kind` plus fields for that kind.

### `huggingface_file`

Downloads a single file from a Hugging Face repo into a ComfyUI model directory.

```json
{
  "name": "Example VAE",
  "kind": "huggingface_file",
  "repo_id": "org/repo",
  "filename": "path/in/repo/model.safetensors",
  "destination": "vae/model.safetensors"
}
```

### `huggingface_snapshot`

Downloads a repo snapshot into the Hugging Face cache layout. This is useful for LLM-style repos with many files.

```json
{
  "name": "Example LLM",
  "kind": "huggingface_snapshot",
  "repo_id": "org/repo",
  "cache_subdir": "LLM/cache",
  "allow_patterns": ["*.json", "*.safetensors", "*.txt"]
}
```

### `civitai_version`

Downloads the primary file for a CivitAI model version id.

```json
{
  "name": "Example Checkpoint",
  "kind": "civitai_version",
  "version_id": "123456",
  "destination": "checkpoints/example.safetensors"
}
```

## Where to put things

Use destinations relative to `/workspace/ComfyUI/models`.

Common folders:

- `checkpoints/`
- `diffusion_models/`
- `text_encoders/`
- `vae/`
- `loras/`
- `embeddings/`
- `controlnet/`
- `clip/`
- `clip_vision/`
- `upscale_models/`

## Adding a new LoRA

Example Hugging Face LoRA:

```json
{
  "name": "My LoRA",
  "kind": "huggingface_file",
  "repo_id": "owner/my-lora-repo",
  "filename": "my_lora.safetensors",
  "destination": "loras/my_lora.safetensors"
}
```

Example CivitAI LoRA:

```json
{
  "name": "My CivitAI LoRA",
  "kind": "civitai_version",
  "version_id": "1234567",
  "destination": "loras/my_civitai_lora.safetensors"
}
```

## Adding a different model type

Follow the same pattern and change only the destination:

- text encoder: `text_encoders/...`
- VAE: `vae/...`
- diffusion model: `diffusion_models/...`
- checkpoint: `checkpoints/...`

## Notes

- The bootstrap script logs warnings and keeps startup going if a download fails.
- If you want stricter behavior later, we can add a fail-fast mode.
