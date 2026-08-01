#!/usr/bin/env python3
from pathlib import Path
import hashlib
import shutil
import tarfile


root = Path(__file__).resolve().parent
parts_dir = root / "parts"
archive_path = root / "qwen2.5-coder-7b.tar"
parts = sorted(parts_dir.glob("qwen2.5-coder-7b.tar.part-*"))

if not parts:
    raise SystemExit("No model parts found in ./parts")

print(f"Joining {len(parts)} parts...")
with archive_path.open("wb") as output:
    for index, part in enumerate(parts, 1):
        print(f"[{index}/{len(parts)}] {part.name}")
        with part.open("rb") as source:
            shutil.copyfileobj(source, output, length=16 * 1024 * 1024)

expected = (parts_dir / "archive.sha256").read_text(encoding="ascii").strip().lower()
digest = hashlib.sha256()
with archive_path.open("rb") as source:
    while chunk := source.read(16 * 1024 * 1024):
        digest.update(chunk)

actual = digest.hexdigest()
if actual != expected:
    archive_path.unlink(missing_ok=True)
    raise SystemExit(f"SHA256 mismatch\nExpected: {expected}\nActual:   {actual}")

destination = Path.home() / ".ollama"
destination.mkdir(parents=True, exist_ok=True)
print(f"Extracting to {destination}...")
with tarfile.open(archive_path, "r") as archive:
    # The archive is generated locally by build-package.ps1 and verified above.
    # Avoid the newer filter= argument so this also works with older macOS Python 3.
    archive.extractall(destination)

archive_path.unlink()
print("Restored qwen2.5-coder:7b successfully.")
print("Verify with: ollama list")
