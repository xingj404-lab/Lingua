#!/usr/bin/env python3
"""Collect redistributed dependency license texts from the resolved Xcode checkouts."""
import json, os, shutil
from pathlib import Path
root = Path(__file__).resolve().parent.parent
checkout = Path(os.environ.get('LINGUA_CHECKOUTS', str(root / 'build/SourcePackages/checkouts')))
out = root / 'Sources/LinguaMac/Resources/Legal/ThirdParty'
out.mkdir(parents=True, exist_ok=True)
count = 0
repos = {repo.name: repo for repo in checkout.iterdir() if repo.is_dir()}
# Local overrides must contribute their own license even on a clean checkout.
local_mlx = root / 'Vendor/mlx-swift'
if local_mlx.is_dir():
    repos['mlx-swift'] = local_mlx
    repos['mlx-core'] = local_mlx / 'Source/Cmlx/mlx'
for name, repo in sorted(repos.items()):
    files = [p for p in repo.iterdir() if p.is_file() and (p.name.lower().startswith(('license','licence','copying','notice')))]
    if not files: raise SystemExit('Missing license: ' + repo.name)
    folder = out / name; folder.mkdir(exist_ok=True)
    for file in files:
        target = folder / file.name
        if target.exists(): target.chmod(target.stat().st_mode | 0o200)
        shutil.copy2(file, target)
        target.chmod(target.stat().st_mode | 0o200)
    count += 1
if not count: raise SystemExit('No resolved dependency licenses found')
model = out / 'Hy-MT2'; model.mkdir(exist_ok=True)
for file in (root / 'scripts/model-licenses/Hy-MT2').iterdir():
    if file.is_file():
        target = model / file.name
        if target.exists(): target.chmod(target.stat().st_mode | 0o200)
        shutil.copy2(file, target)
        target.chmod(target.stat().st_mode | 0o200)
print('Included licenses for', count, 'dependencies and Hy-MT2')
