# RDNA2 Ray Accelerator Research: Repurposing RT Hardware for Rasterized Frames

[![Vulkan 1.3](https://img.shields.io/badge/Vulkan-1.3%20%2F%201.4-red.svg)](https://www.vulkan.org/)
[![Hardware](https://img.shields.io/badge/GPU-AMD%20Radeon%20RX%206700%20XT-blue.svg)](https://www.amd.com/)
[![Driver](https://img.shields.io/badge/Driver-Mesa%20RADV%2026.2.5%20(ACO)-orange.svg)](https://docs.mesa3d.org/drivers/radv.html)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

An empirical research suite and benchmarking framework investigating whether AMD RDNA2 dedicated Ray Accelerators (RA) can raise FPS in modern rasterized graphics workloads on Linux using Vulkan ray queries (`VK_KHR_ray_query`) and Mesa RADV.

---

## Motivation & Core Philosophy

Modern graphics cards and current-generation consoles (PS5, Xbox Series X/S, RDNA2/3/4, RTX) dedicate significant physical die area to specialized ray tracing hardware. In pure-raster games and esports engines, **this hardware sits 100% idle throughout the entire frame**. Conversely, enabling traditional "full" ray tracing often slashes frame rates by 50% to 70%, forcing aggressive spatial and temporal upscaling.

This research began with a straightforward question of **hardware resource optimization**:

> *Can we repurpose otherwise idle Ray Accelerator silicon to accelerate a standard rasterized frame — either by overlapping compute passes during raster hardware bubbles via async compute, or by replacing expensive, multi-pass raster techniques at equal or superior image quality?*

Rather than treating ray tracing as an all-or-nothing visual luxury, this framework audits where the hardware architecture provides authentic speedups ($O(\text{pixels} \cdot \log(\text{triangles}))$) versus where traditional rasterization, hierarchical Z-buffering (HZB), and on-chip Local Data Share (LDS) remain decisively superior.

---

## Real-World Engine Applications & Practical Insights

### 1. Scaling to Many Dynamic Shadow Casters (Night, Urban & Dungeon Scenes)
- **The Raster Bottleneck:** In traditional engines, every dynamic shadow-casting light requires re-rasterizing the scene into a shadow map target (cube maps, dual paraboloids, or atlas partitions). Supporting 16 to 64 dynamic casters in a 1M+ triangle scene forces geometry pipelines to process tens of millions of vertices, causing shadow generation alone to consume **13 ms to 54 ms**.
- **The Ray Query Solution:** Instead of rasterizing $N$ shadow maps, the engine renders a standard G-buffer once and tests shadow visibility inline via ray queries in a tiled deferred compute pass. Testing 16 to 64 dynamic shadow lights costs only **0.18 ms to 0.93 ms** (**up to 132x speedup**), completely eliminating shadow atlas memory allocation, bias tuning, and cascade edge swimming.

### 2. "Free" High-Fidelity Geometric AO via Async Compute Pipeline Packing
- **The Hardware Bubble:** During early frame rasterization (Depth Prepass, Shadow Maps), shaders write only depth and perform zero texture sampling. On RDNA2, Ray Accelerators share execution datapath and addressing units with the Texture Mapping Units (TMUs). During depth-only passes, the TMUs and Ray Accelerators sit idle.
- **The Ray Query Solution:** By dispatching a Ray Query Ambient Occlusion (RQAO) pass on a dedicated **Async Compute queue** concurrently with the depth prepass, the workload achieves **94.1% overlap efficiency**. This delivers true world-space contact occlusion essentially for free, raising frame rates by **+52.0% FPS** compared to serialized execution, while avoiding the +6.2% TMU contention penalty incurred if overlapped with a texture-heavy G-buffer.

### 3. Planar Reflections for Open-World Water, Mirrors & Cockpits
- **The Raster Bottleneck:** Simulating planar mirrors, vehicle rearview mirrors, or water surfaces typically requires an entire second camera render pass with an oblique clipping plane. This duplicates scene draw calls, vertex shading, and culling overhead ($O(\text{triangles})$).
- **The Ray Query Solution:** Ray Query reflection cost scales strictly with the number of reflective pixels on screen ($O(\text{reflective pixels} \times \log(\text{triangles}))$). For scenes $\ge 500\text{k}$ triangles, Ray Query planar reflections beat a second raster pass across all screen coverage fractions (yielding **12x to 60x speedups** on puddles and vehicle mirrors at 2%–15% screen coverage, and **2.4x to 7.9x speedups** on full-screen mirrors).

### 4. Direct Replacement of Screen-Space Ambient Occlusion (SSAO)
- **The Screen-Space Flaw:** SSAO / GTAO suffers from haloing around foreground silhouettes, false occlusion under grazing camera angles, and disocclusion voids when occluding geometry exits the camera frustum.
- **The Ray Query Solution:** At 1 SPP with a bilateral filter, RQAO executes in **0.504 ms** — matching the 0.508 ms cost of 16-sample SSAO — while boosting visual fidelity by **+19.7 dB PSNR**. It provides exact geometric contact shadows and ambient occlusion at zero additional frame budget.

### 5. Architectural Anti-Patterns: Where NOT to Use Ray Accelerators
- **Do NOT run BVH refits on Async Compute:** In-place BVH refits are memory-bandwidth bound. Running dynamic mesh refits on async compute during graphics passes saturates L2 and Infinity Cache, causing a **-7.3% overlap efficiency penalty** that degrades total frame time.
- **Do NOT replace Tiled/Clustered LDS Deferred Lighting:** Generating light lists using on-chip 0-cycle LDS registers is **3x to 7x faster** than traversing BVH light hierarchies in global memory.
- **Do NOT use Ray Queries for Occlusion Culling:** Two-pass Temporal Hierarchical Z-Buffering (HZB) executes in <0.04 ms with 0% visibility popping, whereas multi-ray bounding-box queries suffer **58.6% false-negative leaks** on thin gaps.

---

## Key Highlights & Findings

For the complete forensic audit, methodology, crossover analyses, and data tables, see [**`REPORT.md`**](REPORT.md).

```
                                  RDNA2 WORKLOAD VERDICTS
  ┌───────────────────────────────────────────────┬───────────────────────────────────────────────┐
  │              WHERE THE RA WINS                │              DO NOT BOTHER (LOSSES)           │
  ├───────────────────────────────────────────────┼───────────────────────────────────────────────┤
  │ • Shadows with ≥4 Casters: Up to 132x speedup │ • Dynamic BVH Refit on Async: Memory bus/L2   │
  │ • Async Overlap with Depth: 94% efficiency    │   contention causes -7.3% efficiency drop.    │
  │ • Planar Reflections: Up to 60x speedup       │ • Screen-Space Reflections (SSR): SSR is      │
  │ • Ambient Occlusion (RQAO): +19.7 dB PSNR at  │   0.08 ms vs RQR 0.42 ms (quality cost).      │
  │   equal frame time (0.50 ms)                  │ • Many-Light Shading: Tiled LDS is 3x–7x      │
  │ • Full-Frame Pipeline: +125% FPS at 1080p     │   faster than Ray Query light lookup.         │
  │   (2.25x speedup, 237 vs 105 FPS)             │ • Primary Visibility with Active LOD:         │
  │                                               │   Mesh shaders match RQ with 0 MB BLAS.       │
  └───────────────────────────────────────────────┴───────────────────────────────────────────────┘
```

### Full-Frame Benchmark Comparison (1080p & 1440p)
| Resolution | Raster Baseline | RA-Assisted (Serial) | RA-Assisted (Async Overlap) | Dynamic Scene (+Refit) | Speedup / Gain |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1080p** | 9.51 ms (105 FPS) | **4.22 ms (237 FPS)** | **4.25 ms (235 FPS)** | **4.80 ms (208 FPS)** | **+125.5% FPS (2.25x)** |
| **1440p** | 11.11 ms (90 FPS) | **6.65 ms (150 FPS)** | **6.77 ms (148 FPS)** | **7.23 ms (138 FPS)** | **+67.1% FPS (1.67x)** |

---

## Visual Benchmark Results

<p align="center">
  <img src="results/expE_fullframe.png" width="48%" />
  <img src="results/expA_async.png" width="48%" />
</p>
<p align="center">
  <img src="results/expB_shadows.png" width="48%" />
  <img src="results/expC_reflections.png" width="48%" />
</p>

---

## Repository Structure

- [`common/`](common/): Vulkan context initialization, dual-queue timer (`DualQueueTimer`), async compute queue management, BLAS/TLAS builders, GLSL compilation via shaderc, and PSNR/SSIM image metrics.
- [`expA_async/`](expA_async/): Async compute overlap benchmarks and TMU contention tests.
- [`expB_shadows/`](expB_shadows/): Dynamic shadow caster sweep ($1$ to $64$ lights, $100\text{k}$ to $2.5\text{M}$ triangles).
- [`expC_reflections/`](expC_reflections/): Planar mirror reflector sweep across screen coverage % and scene geometry.
- [`expD_screenspace/`](expD_screenspace/): Screen-space effects replacement (SSAO vs RQAO, SSR vs RQR, SSCS vs RQCS).
- [`expE_fullframe/`](expE_fullframe/): Full realistic deferred frame integrating shadows, reflections, and AO.
- [`exp0_probe/`](exp0_probe/): Hardware Ray Accelerator capability probes and microbenchmarks.
- [`exp1_visbuf/`](exp1_visbuf/): Visibility buffer subpixel rasterization vs ray-query benchmarks.
- [`exp2_occlusion/`](exp2_occlusion/): Occlusion culling showdown: Ray Query vs Temporal HZB.
- [`exp3_spatial/`](exp3_spatial/): Spatial lighting data structures vs Clustered/Tiled deferred shading.
- [`exp4_integration/`](exp4_integration/): Earlier many-light radius sweep integration suite.
- [`scripts/`](scripts/): Automated Python plotting scripts using Matplotlib and NumPy.
- [`results/`](results/): Raw CSV data dumps and publication-quality generated figures.

---

## Building and Running

### Prerequisites
- **OS:** Linux (`x86_64`)
- **GPU:** AMD Radeon RX 6000 series (RDNA2) or newer
- **Vulkan Driver:** Mesa RADV (`vulkan-radeon`) with `VK_KHR_ray_query` support
- **Dependencies:** CMake 3.20+, GCC / Clang (C++20), Vulkan SDK (`vulkan-headers`, `spirv-tools`, `shaderc`), Python 3 with `matplotlib` and `pandas`

### Build and Run All Experiments
```bash
# Clone the repository
git clone https://github.com/<username>/racores.git
cd racores

# Run the complete test suite (compiles binaries, runs all 10 benchmarks, outputs plots)
./run_all.sh
```

---

## Detailed Report

For the in-depth forensic analysis, full methodology, and architectural breakdown, refer to [**`REPORT.md`**](REPORT.md).
