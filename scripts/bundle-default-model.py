#!/usr/bin/env python3
"""Package the verified local Hy-MT2 snapshot; never download weights."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

repository = "mlx-community/Hy-MT2-1.8B-4bit"
namespace = hashlib.sha256(("https://hf-mirror.com/" + repository).encode()).hexdigest()
cache = Path.home() / "Library/Application Support/LinguaMac/Models"
source_dir = cache / namespace
source_manifest = source_dir / ".lingua-manifest.json"
source = Path(os.environ["LINGUA_DEFAULT_MODEL_DIR"]) if os.environ.get("LINGUA_DEFAULT_MODEL_DIR") else None
if source:
    source_manifest = source / ".lingua-manifest.json"
manifest = json.loads(source_manifest.read_text())
revision = manifest["revision"]
assert len(revision) == 40 and all(c in "0123456789abcdef" for c in revision)
source = source or source_dir / revision
destination_dir = Path(sys.argv[1]) / "BundledModels" / namespace
destination = destination_dir / revision
for entry in manifest["entries"]:
    relative = Path(entry["path"])
    assert not relative.is_absolute() and ".." not in relative.parts
    original = source / relative
    assert original.is_file() and not original.is_symlink(), original
    assert original.stat().st_size == entry.get("lfs", {}).get("size", entry.get("size")), original
    if "lfs" in entry:
        with original.open("rb") as stream:
            digest = hashlib.sha256()
            for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""): digest.update(chunk)
            assert digest.hexdigest() == entry["lfs"]["oid"], original
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists() or target.stat().st_mtime_ns != original.stat().st_mtime_ns or target.stat().st_size != original.stat().st_size:
        # Independent APFS copy-on-write copies keep the bundle movable while saving build disk space.
        if subprocess.run(["/bin/cp", "-c", "-p", str(original), str(target)], capture_output=True).returncode:
            shutil.copy2(original, target)
manifest["repository"] = repository
destination_dir.mkdir(parents=True, exist_ok=True)
for target in [destination_dir / ".lingua-manifest.json", destination / ".lingua-manifest.json"]:
    target.write_text(json.dumps(manifest))
licenses = Path(__file__).parent / "model-licenses/Hy-MT2"
assert (licenses / "LICENSE.txt").is_file(), "Missing model redistribution license"
shutil.copytree(licenses, destination / "Licenses", dirs_exist_ok=True)
print("Bundled Hy-MT2:", sum(e.get("lfs", {}).get("size", e.get("size", 0)) for e in manifest["entries"]), "bytes")
