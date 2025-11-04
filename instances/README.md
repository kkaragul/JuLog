# Benchmark Instances for MSHH Framework

This directory contains benchmark instances for all 8 problem domains supported by the MSHH framework.

## 📚 Directory Structure

```
instances/
├── tsp/              # Traveling Salesman Problem
├── cvrp/             # Capacitated Vehicle Routing Problem
├── cvrptw/           # CVRP with Time Windows
├── evrp/             # Electric Vehicle Routing Problem
├── co2vrp/           # Green Vehicle Routing Problem
├── binpacking/       # Bin Packing Problem
├── jobshop/          # Job Shop Scheduling
└── flowshop/         # Flow Shop Scheduling
```

---

## 🚀 Quick Start

### Download/Create Sample Instances

```bash
cd backend
julia scripts/download_benchmarks.jl all
```

This creates sample instances for all domains.

### Solve Instances in Batch

```bash
# Solve all TSP instances
julia scripts/batch_solve.jl tsp --time-limit 60

# Solve with custom parameters
julia scripts/batch_solve.jl cvrp --time-limit 300 --output my_results/
```

---

## 📦 Benchmark Instance Sources

### TSP (Traveling Salesman Problem)

**Standard Benchmarks:**
- **TSPLIB**: http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/
- **8th DIMACS Challenge**: http://dimacs.rutgers.edu/programs/challenge/tsp/

**Popular Instances:**
- `eil51.tsp` - 51 cities, optimal: 426
- `berlin52.tsp` - 52 cities, optimal: 7542
- `st70.tsp` - 70 cities, optimal: 675
- `eil76.tsp` - 76 cities, optimal: 538
- `kroA100.tsp` - 100 cities, optimal: 21282
- `kroB100.tsp` - 100 cities, optimal: 22141
- `ch130.tsp` - 130 cities, optimal: 6110
- `ch150.tsp` - 150 cities, optimal: 6528

**Format:** TSPLIB format (`.tsp`)

**Manual Download:**
```bash
wget http://comopt.ifi.uni-heidelberg.de/software/TSPLIB95/tsp/eil51.tsp.gz
gunzip eil51.tsp.gz
mv eil51.tsp instances/tsp/
```

---

### CVRP (Capacitated Vehicle Routing)

**Standard Benchmarks:**
- **CVRPLIB**: http://vrp.galgos.inf.puc-rio.br/index.php/en/
- **Uchoa et al. (2017)**: New benchmark instances
- **Golden et al.**: Classic instances
- **Augerat et al.**: Set A, B, P instances

**Popular Instances:**
- `A-n32-k5.vrp` - 32 customers, 5 vehicles
- `B-n31-k5.vrp` - 31 customers, 5 vehicles
- `E-n22-k4.vrp` - 22 customers, 4 vehicles
- `P-n16-k8.vrp` - 16 customers, 8 vehicles
- `X-n101-k25.vrp` - 101 customers, 25 vehicles

**Format:** VRPLIB format (`.vrp`)

**Resources:**
- CVRPLIB: http://vrp.atd-lab.inf.puc-rio.br/
- VRP-REP: http://www.vrp-rep.org/

---

### CVRPTW (CVRP with Time Windows)

**Standard Benchmarks:**
- **Solomon Benchmarks**: Classic VRPTW instances
  - C1, C2: Clustered customers
  - R1, R2: Random customers
  - RC1, RC2: Mixed random-clustered

**Popular Instances:**
- `C101.txt` - 100 customers, tight time windows
- `C201.txt` - 100 customers, wide time windows
- `R101.txt` - 100 customers, random
- `RC101.txt` - 100 customers, mixed

**Best Known Solutions:**
- http://w.cba.neu.edu/~msolomon/problems.htm
- http://www.sintef.no/projectweb/top/vrptw/

**Format:** Solomon format (`.txt`)

---

### EVRP (Electric Vehicle Routing)

**Standard Benchmarks:**
- **Schneider et al. (2014)**: E-VRP with time windows
- **Keskin & Çatay (2016)**: Partial recharge instances

**Instance Sets:**
- Small: 5-10 customers
- Medium: 15-25 customers
- Large: 50-100 customers

**Format:** Extended VRPLIB with battery/charging info (`.evrp`)

**Research Papers:**
- Schneider, M., et al. (2014). "The electric vehicle-routing problem with time windows and recharging stations"
- Felipe, Á., et al. (2014). "A heuristic approach for the green vehicle routing problem"

---

### CO2VRP (Green Vehicle Routing)

**Standard Benchmarks:**
- Based on CVRP instances with emission parameters
- Green zones and emission factors

**Research References:**
- Bektaş, T., & Laporte, G. (2011). "The Pollution-Routing Problem"
- Demir, E., et al. (2012). "A comparative analysis of several vehicle emission models"

**Format:** VRPLIB + emission parameters (`.vrp`)

---

### Bin Packing Problem

**Standard Benchmarks:**
- **Scholl Datasets**: Classic bin packing instances
- **OR-Library**: http://people.brunel.ac.uk/~mastjjb/jeb/info.html
- **Falkenauer**: Hard instances

**Instance Sets:**
- `N1` - Easy instances
- `N2` - Medium instances
- `N3` - Hard instances
- `N4` - Very hard instances

**Popular Instances:**
- `BPP_N1_50.bpp` - 50 items, easy
- `BPP_N2_100.bpp` - 100 items, medium
- `BPP_N3_200.bpp` - 200 items, hard

**Format:** Simple text format (`.bpp`)

**Resources:**
- OR-Library: http://people.brunel.ac.uk/~mastjjb/jeb/orlib/binpackinfo.html

---

### Job Shop Scheduling

**Standard Benchmarks:**
- **Fisher & Thompson (1963)**: ft06, ft10, ft20
- **Lawrence (1984)**: la01-la40
- **Adams et al. (1988)**: abz5-abz9
- **Applegate & Cook (1991)**: orb01-orb10
- **Taillard (1993)**: ta01-ta80

**Popular Instances:**
- `ft06.txt` - 6 jobs, 6 machines, optimal: 55
- `ft10.txt` - 10 jobs, 10 machines, optimal: 930
- `la01.txt` - 10 jobs, 5 machines, optimal: 666
- `la16.txt` - 10 jobs, 10 machines, optimal: 945
- `orb01.txt` - 10 jobs, 10 machines, optimal: 1059

**Format:** Standard JSP format (`.txt`)

**Resources:**
- OR-Library: http://people.brunel.ac.uk/~mastjjb/jeb/orlib/jobshopinfo.html
- Job Shop Instances: http://jobshop.jjvh.nl/

---

### Flow Shop Scheduling

**Standard Benchmarks:**
- **Taillard (1993)**: ta001-ta120
  - 20 jobs: ta001-ta010 (5, 10, 20 machines)
  - 50 jobs: ta021-ta030 (5, 10, 20 machines)
  - 100 jobs: ta051-ta060 (5, 10, 20 machines)
  - 200 jobs: ta081-ta090 (10, 20 machines)
  - 500 jobs: ta111-ta120 (20 machines)

**Popular Instances:**
- `tai20_5.txt` - 20 jobs, 5 machines
- `tai20_10.txt` - 20 jobs, 10 machines
- `tai50_5.txt` - 50 jobs, 5 machines
- `tai100_10.txt` - 100 jobs, 10 machines

**Best Known Solutions:**
- http://mistic.heig-vd.ch/taillard/problemes.dir/ordonnancement.dir/ordonnancement.html

**Format:** Taillard format (`.txt`)

---

## 📊 Instance Statistics

### Current Sample Instances

After running `download_benchmarks.jl all`:

| Domain | Count | Sizes | Extensions |
|--------|-------|-------|------------|
| TSP | 4 | 30, 50, 100, 200 cities | `.tsp` |
| CVRP | 3 | 25, 50, 100 customers | `.vrp` |
| CVRPTW | 3 | 25, 50, 100 customers | `.txt` |
| EVRP | 3 | 20, 40, 60 customers | `.evrp` |
| CO2VRP | 3 | (based on CVRP) | `.vrp` |
| BinPacking | 3 | 50, 100, 200 items | `.bpp` |
| JobShop | 4 | 6x6, 10x10, 20x5, 20x10 | `.txt` |
| FlowShop | 5 | 20x5, 20x10, 50x5, 50x10, 100x5 | `.txt` |

---

## 🔧 Adding Custom Instances

### Step 1: Add Instance File

```bash
# Example: Add a new TSP instance
cp my_instance.tsp instances/tsp/
```

### Step 2: Verify Format

Each domain has specific format requirements. Check the parser in:
- `backend/src/utils/parsers.jl`

### Step 3: Test Parsing

```bash
julia -e '
include("src/MSHH.jl")
using .MSHH.Parsers
instance = parse_tsp("instances/tsp/my_instance.tsp")
println("Parsed: ", instance.name)
'
```

### Step 4: Solve

```bash
# Single instance via API
curl -X POST http://localhost:8000/api/solve/tsp \
  -H "Content-Type: application/json" \
  -d '{"instance_file": "instances/tsp/my_instance.tsp", "time_limit": 60}'

# Or batch solve
julia scripts/batch_solve.jl tsp
```

---

## 📝 File Format Examples

### TSP Format (TSPLIB)

```
NAME: test
TYPE: TSP
DIMENSION: 4
EDGE_WEIGHT_TYPE: EUC_2D
NODE_COORD_SECTION
1 38.24 20.42
2 39.57 26.15
3 40.56 25.32
4 36.26 23.12
EOF
```

### CVRP Format (VRPLIB)

```
NAME : test
TYPE : CVRP
DIMENSION : 5
CAPACITY : 100
EDGE_WEIGHT_TYPE : EUC_2D
NODE_COORD_SECTION
1 40 50
2 30 40
3 50 30
4 35 45
5 45 35
DEMAND_SECTION
1 0
2 15
3 20
4 10
5 25
DEPOT_SECTION
1
-1
EOF
```

### Solomon Format (CVRPTW)

```
C101

VEHICLE
NUMBER     CAPACITY
  25         200

CUSTOMER
CUST NO.  XCOORD.   YCOORD.    DEMAND   READY TIME  DUE DATE   SERVICE TIME
    0       40        50          0          0       1236          0
    1       45        68         10        912        967         90
    2       45        70         30        825        870         90
```

---

## 🎯 Benchmarking Best Practices

### 1. Multiple Runs

Run each instance multiple times for statistical significance:

```bash
for i in {1..10}; do
    julia scripts/batch_solve.jl tsp --time-limit 60 --output run_$i/
done
```

### 2. Parameter Tuning

Create custom parameter files:

```json
{
    "tau": 0.020,
    "d": 12.0,
    "s1": 25.0,
    "s2": 7,
    "PS2HH": 0.4
}
```

Use with:
```bash
julia scripts/batch_solve.jl tsp --params custom_params.json
```

### 3. Result Analysis

Results are saved in CSV format with:
- Initial objective
- Best objective
- Improvement %
- Computation time
- Algorithm statistics

### 4. Comparison with Literature

When reporting results, compare with:
- Best known solutions (BKS)
- State-of-the-art methods
- Standard benchmarks from literature

---

## 📖 References

### VRP Benchmarks
- Uchoa, E., et al. (2017). "New benchmark instances for the Capacitated Vehicle Routing Problem"
- Solomon, M. M. (1987). "Algorithms for the vehicle routing and scheduling problems with time window constraints"

### Scheduling Benchmarks
- Taillard, E. (1993). "Benchmarks for basic scheduling problems"
- OR-Library: http://people.brunel.ac.uk/~mastjjb/jeb/info.html

### Online Resources
- CVRPLIB: http://vrp.atd-lab.inf.puc-rio.br/
- VRP Resources: https://w1.cirrelt.ca/~vidalt/en/VRP-resources.html
- Job Shop Benchmarks: http://jobshop.jjvh.nl/

---

## 🤝 Contributing Instances

If you have new benchmark instances:

1. Ensure proper format
2. Include optimal/best-known solutions if available
3. Cite the source
4. Add to appropriate directory
5. Update this README

---

*Last updated: November 2025*
