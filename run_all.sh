#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export PATH="$HOME/.local/bin:$PATH"

echo "============================================================"
echo " RDNA2 RAY ACCELERATOR RESEARCH: AUTOMATED BENCHMARK SUITE"
echo "============================================================"

# 1. Build
echo -e "\n[1/6] Building all project binaries..."
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# 2. Phase 0 Probe
echo -e "\n[2/6] Running Phase 0 Capability Probe..."
./build/exp0_probe/probe_main

# 3. Phase 1 Microbenchmarks
echo -e "\n[3/6] Running Phase 1 RA Microbenchmarks..."
./build/exp0_probe/microbench_main

# 4. Phase 2 Experiment 1: Primary Visibility Buffer
echo -e "\n[4/6] Running Phase 2: Visibility Buffer Ray-Cast vs Raster..."
./build/exp1_visbuf/visbuf_main

# 5. Phase 3 Experiment 2: Occlusion Culling
echo -e "\n[5/6] Running Phase 3: Occlusion Culling vs HZB..."
./build/exp2_occlusion/occlusion_main

# 6. Phase 4 Experiment 3: Spatial Lighting Queries
echo -e "\n[6/6] Running Phase 4: Spatial Light Lookup vs Clustered Lighting..."
./build/exp3_spatial/spatial_main

# 7. Phase 5 Full Frame Integration (Earlier Benchmark)
echo -e "\nRunning Earlier Full Frame Integration Benchmark..."
./build/exp4_integration/integration_main

# 8. Experiment A: Async Compute Overlap
echo -e "\nRunning Experiment A: Async Compute Overlap..."
./build/expA_async/async_main

# 9. Experiment B: Shadows with Many Casters
echo -e "\nRunning Experiment B: Shadows with Many Casters..."
./build/expB_shadows/shadows_main

# 10. Experiment C: Planar Reflections / Mirrors
echo -e "\nRunning Experiment C: Planar Reflections / Mirrors..."
./build/expC_reflections/reflections_main

# 11. Experiment D: Screen-Space Effects Replacement
echo -e "\nRunning Experiment D: Screen-Space Effects Replacement..."
./build/expD_screenspace/screenspace_main

# 12. Experiment E: Full-Frame Realistic Integration
echo -e "\nRunning Experiment E: Full-Frame Realistic Integration (1080p & 1440p)..."
./build/expE_fullframe/fullframe_main

# 13. Generate Plots
echo -e "\nGenerating all result plots..."
/home/folk/.local/venv/bin/python3 scripts/plot_exp0.py
/home/folk/.local/venv/bin/python3 scripts/plot_exp1.py
/home/folk/.local/venv/bin/python3 scripts/plot_exp2.py
/home/folk/.local/venv/bin/python3 scripts/plot_exp3.py
/home/folk/.local/venv/bin/python3 scripts/plot_exp4.py
/home/folk/.local/venv/bin/python3 scripts/plot_expA.py
/home/folk/.local/venv/bin/python3 scripts/plot_expB.py
/home/folk/.local/venv/bin/python3 scripts/plot_expC.py
/home/folk/.local/venv/bin/python3 scripts/plot_expD.py
/home/folk/.local/venv/bin/python3 scripts/plot_expE.py

echo -e "\n============================================================"
echo " ALL BENCHMARKS AND PLOTS GENERATED SUCCESSFULLY!"
echo " Results available in results/ and documented in REPORT.md"
echo "============================================================"
