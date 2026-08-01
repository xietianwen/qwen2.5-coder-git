# qwen2.5-coder:7b offline Git package

This repository carries the Ollama `qwen2.5-coder:7b` model as ordinary Git
files smaller than GitHub's 100 MiB per-file limit. The source model manifest
and only its referenced blobs are included.

## Restore on macOS

At least 15 GB of free disk space is recommended during restoration.

```bash
git clone REPOSITORY_URL qwen2.5-coder-git
cd qwen2.5-coder-git
python3 restore.py
ollama list
ollama run qwen2.5-coder:7b
```

The restore script joins all parts, verifies the archive SHA-256, extracts the
model into `~/.ollama/models`, and removes the temporary joined TAR file.

Do not rename, modify, or omit any file under `parts/`.

## Push to GitHub from Windows

Create an empty GitHub repository without generated README/license files, then:

```powershell
.\push-in-batches.ps1 -RepositoryUrl https://github.com/OWNER/REPOSITORY.git
```

The script commits and pushes eight parts at a time and can be rerun after a
network interruption. Do not use Git LFS: the Mac environment is expected to
retrieve everything through ordinary Git.
