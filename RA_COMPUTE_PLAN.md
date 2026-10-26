# Project: Using RDNA2 Ray Accelerators for Non-RT Rendering Work

## Goal
Find out, with measurements, whether the RDNA2 Ray Accelerator (RA) can speed up
normal raster-pipeline work via Vulkan ray queries (`VK_KHR_ray_query`) on Linux/RADV.
A clear "no, here is why" backed by data is a valid outcome. Do not assume it will win.

## Background (what is known)
- Each RDNA2 CU has one RA. It only does ray-box and ray-triangle tests.
- BVH traversal itself runs on the shader ALUs (stack in LDS). There is no hardware traversal on RDNA2.
- Ray queries compile to `image_bvh_intersect_ray`. The RA shares the texture/memory path.
- Therefore costs to watch: ALU for traversal, LDS stack, BVH memory bandwidth, BVH build/update time.
- The RA is only "idle" in pure-raster workloads. Any gain must beat the cost of building and storing a BVH.

## Environment
- Linux, Mesa RADV (recent Mesa; verify RT is enabled, older versions needed `RADV_PERFTEST=rt`).
- Vulkan SDK, glslang or slangc, CMake, C++20.
- Tools: `vulkaninfo`, Radeon GPU Profiler (RGP) if available, `RADV_DEBUG=shaders` to dump ISA.
- Windowing optional. Prefer headless compute plus offscreen render targets for benchmarks.

## Empirical Methodology & Experimental Rules
1. Measure first. Every claim needs a number (GPU timestamp queries, median of 100+ frames, warmup discarded).
2. Every experiment has a non-RA baseline (plain compute or hardware raster). No baseline, no result.
3. Verify correctness against a CPU or brute-force reference before benchmarking anything.
4. Confirm the RA is actually used: dump ISA and grep for `image_bvh_intersect_ray`.
5. Keep experiments self-contained in their own folders. Shared code only in `common/`.
6. Report negative results honestly. Do not tune one side to flatter the other.
7. Pin and record: GPU model, clocks (fix with `power_dpm_force_performance_level` if possible), Mesa version, kernel version.

## Repo layout
```
common/        Vulkan init, buffers, BVH build helpers, timestamp queries, CSV output
exp0_probe/    capability check + RA microbenchmark
exp1_visbuf/   primary visibility: ray-cast vs raster crossover
exp2_occlusion/ occlusion culling via ray queries vs HZB compute
exp3_spatial/  point/volume lookups (lights, probes) via degenerate rays
results/       CSVs + plots
REPORT.md      final findings
```

## Phase 0: Setup and capability probe (exp0_probe)
- [ ] Create Vulkan instance/device with `rayQuery`, `accelerationStructure`, `bufferDeviceAddress`, `timestampQuery`.
- [ ] Print device name, driver version, confirm features via `vulkaninfo`.
- [ ] Build a trivial TLAS/BLAS (single triangle, then a grid of boxes via AABB geometry).
- [ ] Run a compute shader that fires N ray queries and writes hits; verify results on CPU.
- [ ] Dump ISA, confirm `image_bvh_intersect_ray` is present.
- **Gate:** if rayQuery does not work on this setup, stop and report why.

## Phase 1: RA microbenchmark (exp0_probe)
Goal: know the raw ceiling.
- [ ] Rays/sec for coherent vs incoherent rays against scenes of 1k, 100k, 1M triangles.
- [ ] Same query implemented in software (compute shader BVH traversal using ALUs only) for comparison.
- [ ] Measure with RA workload running concurrently with a texture-heavy workload to quantify texture-path contention.
- [ ] Measure BVH build time and refit/update time vs scene size (`vkCmdBuildAccelerationStructuresKHR`, build vs update mode).
- Output: CSV + short summary of throughput, build cost, contention penalty.

## Phase 2: Experiment 1, primary visibility ray-cast vs raster (exp1_visbuf)
Hypothesis: for sub-pixel/micro triangles, ray-cast visibility beats hardware raster (quad overshading).
- [ ] Generate synthetic meshes with controlled average triangle size (0.25 px to 32 px area).
- [ ] Baseline A: hardware raster to a visibility buffer (triangle ID + depth).
- [ ] Baseline B: compute-shader software rasterizer (optional, only if time allows).
- [ ] Test: one primary ray per pixel via ray query, writing the same visibility buffer.
- [ ] Verify the visibility buffers match (allow tiny edge differences, report mismatch %).
- [ ] Sweep triangle size and resolution (1080p, 1440p); find the crossover point if one exists.
- Output: plot of frame time vs triangle size for each method.

## Phase 3: Experiment 2, occlusion culling via ray queries (exp2_occlusion)
Hypothesis: casting rays to object bounds against an occluder BVH can match or beat HZB culling when a BVH exists anyway.
- [ ] Scene: many instances (10k to 200k) with AABBs; a subset of big occluders.
- [ ] Baseline: standard GPU-driven culling (frustum + HZB occlusion) in compute.
- [ ] Test: per instance, cast rays from camera to AABB center and corners (configurable sample count) against occluder TLAS; instance is visible if any ray reaches it.
- [ ] Compare culling time, false-positive rate (visible but culled wrongly = correctness bug), and false-negative rate (wasted draws).
- [ ] Measure total frame cost including BVH update for dynamic objects.
- Note: frustum tests are not ray tests; keep frustum culling in plain compute and use the RA only for occlusion.

## Phase 4: Experiment 3, spatial queries (exp3_spatial)
Hypothesis: point-in-volume lookups via near-zero-length rays can accelerate clustered light or probe lookup.
- [ ] Represent light volumes as AABB (or sphere via intersection shader is NOT available in ray query, so use AABB/triangle proxies only).
- [ ] Baseline: tiled/clustered light binning in compute.
- [ ] Test: per pixel or per cluster, ray-query enumeration of overlapping light volumes.
- [ ] Sweep light counts (100 to 20k). Compare binning+shading cost end to end.
- Be aware ray queries return closest or any hit one at a time; enumerating all overlaps needs a loop with `rayQueryProceed`. Measure this cost.

## Phase 5: Integration sanity check
- [ ] Take the best-performing experiment and run it inside a simple full frame (raster + lighting) to check the gain survives contention and BVH maintenance.
- [ ] Profile with RGP: is the RA a bottleneck, or are ALU/LDS/memory limiting?

## Phase 6: Report (REPORT.md)
Include: hardware/software versions, methodology, plots, per-experiment verdict
(win / loss / niche win with conditions), explanation of the bottleneck, and a recommendation.
State clearly which results are reproducible and how to rerun them (`./run_all.sh`).

## Success criteria
- Win: any experiment is at least 10% faster end to end than its baseline in a realistic scenario.
- Useful negative: documented crossover points and the reason the RA does not help.
- Either way: reproducible scripts and honest numbers.

## Risks
- BVH build/update cost eats any gain (most likely risk, measure early in Phase 1).
- RA/texture-path contention slows the rest of the frame.
- RADV traversal implementation changes between Mesa versions; record the version.
- Driver bugs: if results look wrong, check against a software traversal before blaming the algorithm.

## References to read first
- RDNA2 ISA guide (`IMAGE_BVH_INTERSECT_RAY`).
- Mesa `src/amd/vulkan/radv_rt_*` and NIR RT lowering for how RADV traverses.
- Chips and Cheese articles on RDNA ray tracing hardware.
- Khronos `VK_KHR_ray_query` spec and samples.
