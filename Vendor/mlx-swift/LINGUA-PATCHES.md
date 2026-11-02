# Lingua MLX backport

Base: mlx-swift 0.32.3, commit 19601207e9a0de51e03ee6ec0c3c5f3784275075.
MLX core: 1f8e74e3f12f31365464a6867c6579f0e9b29d85.

Backport of https://github.com/ml-explore/mlx/pull/4633 (8152d91,
merged as a59cc23 on 2026-10-06), addressing
https://github.com/ml-explore/mlx/issues/4609.

Only core backend/metal/resident.cpp and resident.h are patched.
MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS=1000 renews existing Metal residency
without submitting GPU computations. The refresh worker joins at destruction.
Both root Package.swift and Xcode use this local package to override the
remote transitive identity. Do not rely on editing a SourcePackages cache.
Remove this backport when a compatible Swift release includes the fix.
Original upstream licenses are included.
