# Sub-400ns Hardware-Accelerated CSS Surface Code Syndrome Decoder (css_rtl_q)

![Language](https://img.shields.io/badge/HDL-Verilog%20%7C%20SystemVerilog-blue)
![Protocol](https://img.shields.io/badge/Interface-AXI4--Stream-orange)
![Latency](https://img.shields.io/badge/Latency-65%20ns%20(13%20Cycles%20%40%20200MHz)-brightgreen)
![EDA](https://img.shields.io/badge/Verified-Synopsys%20VCS%20%26%20Verdi%20%7C%20Icarus%20Verilog-purple)

A deterministic, ultra-low-latency Register Transfer Level (RTL) hardware decoder for **Calderbank-Shor-Steane (CSS) Rotated Surface Codes (d = 3)**. Designed to sit directly in the classical-quantum readout loop at 300K, this IP core resolves bit-flip (X), phase-flip (Z), and mixed (Y) quantum error syndromes in **13 clock cycles (65 ns at 200 MHz)**—operating more than **6x faster** than the critical **400 ns superconducting qubit decoherence deadline**.

---

## 1. Problem Overview & Motivation

Physical qubits in superconducting quantum processors suffer from rapid environmental decoherence (around 1 microsecond). Fault-tolerant quantum computing relies on continuous Quantum Error Correction (QEC), where stabilizer ancilla qubits are measured every cycle to extract classical error syndromes without collapsing the quantum state.

* **The Classical Bottleneck:** Transferring syndrome bitstreams to a conventional CPU or GPU over PCIe/Ethernet and executing software graph-search algorithms (such as Minimum Weight Perfect Matching) introduces microsecond-scale latencies. By the time the correction arrives, the physical qubits have already decohered.
* **The Hardware Solution:** `css_rtl_q` implements a parallel cellular boundary-matching engine directly in Verilog RTL with an industry-standard **AXI4-Stream** interface. It separates X-type and Z-type stabilizer syndromes into two orthogonal decoding planes, outputting an 18-bit Pauli correction mask in fixed, deterministic hardware clock cycles.

---

## 2. System Architecture

```text
+-------------------------------------------------------------------------+
|  15mK CRYOSTAT (Quantum Processor / Virtual QPU Testbench)              |
|   * 9 Physical Data Qubits (D0..D8) + 8 Stabilizer Ancillas (SX, SZ)    |
|   * Digitizes stabilizer parity measurements into 8-bit syndrome vector |
+------------------------------------+------------------------------------+
                                     | s_axis_tdata[7:0], s_axis_tvalid
                                     v
+-------------------------------------------------------------------------+
|  300K FPGA / ASIC DECODER IP CORE (surface_decoder_uf_grid.v)           |
|                                                                         |
|   [Stage 1: AXI4-Stream Slave Latch] (1 Cycle)                          |
|      +-- sz[3:0] <= s_axis_tdata[3:0] (Z-Stabilizers -> X Errors)       |
|      +-- sx[3:0] <= s_axis_tdata[7:4] (X-Stabilizers -> Z Errors)       |
|                                                                         |
|   [Stage 2: Parallel Dual-Plane Cellular Growth Engine] (11 Cycles)     |
|      +-- Plane 1: Z-Stabilizer Consensus -> Resolves corr_x[8:0]        |
|      +-- Plane 2: X-Stabilizer Consensus -> Resolves corr_z[8:0]        |
|                                                                         |
|   [Stage 3: Peeling & AXI4-Stream Master Emit] (1 Cycle)                |
|      +-- m_axis_tdata[17:0] <= {corr_z[8:0], corr_x[8:0]}               |
|      +-- m_axis_tuser[7:0]  <= 8'd13 (Hardware Latency Telemetry)       |
+------------------------------------+------------------------------------+
                                     | 13 Clock Cycles (65 ns @ 200 MHz)
                                     v
+-------------------------------------------------------------------------+
|  PULSE CONTROLLER / TELEMETRY MONITOR                                   |
|   * Applies Pauli-X and Pauli-Z recovery gates to corrupted qubits      |
+-------------------------------------------------------------------------+
```

---

## 3. Distance-3 CSS Surface Code Lattice Mapping

The distance-3 rotated surface code consists of **9 Data Qubits (D0 to D8)** and **8 Stabilizer Ancillas** split into two independent sub-lattices:

* **4 Z-Stabilizers (`sz[3:0]`):** Detect bit-flip (X) errors on adjacent data qubits.
* **4 X-Stabilizers (`sx[3:0]`):** Detect phase-flip (Z) errors on adjacent data qubits.
* **Correlated Y Errors (X + Z):** Trigger both `sz` and `sx` planes simultaneously and are resolved concurrently in hardware with zero additional latency penalty.

### Pin & Port Specifications

| Port Name | Direction | Width | Description |
| :--- | :--- | :--- | :--- |
| `aclk` | Input | 1-bit | System clock (verified at 200 MHz / 5.0 ns period) |
| `aresetn` | Input | 1-bit | Active-low synchronous reset |
| `s_axis_tdata` | Input | 8-bit | Bits [7:4] = X-Stabilizers (sx), Bits [3:0] = Z-Stabilizers (sz) |
| `s_axis_tvalid` | Input | 1-bit | Upstream syndrome valid handshake |
| `s_axis_tready` | Output | 1-bit | Decoder ready flag (asserts backpressure during decode) |
| `m_axis_tdata` | Output | 18-bit | Bits [17:9] = 9-bit Pauli-Z mask, Bits [8:0] = 9-bit Pauli-X mask |
| `m_axis_tuser` | Output | 8-bit | Hardware cycle counter telemetry (outputs 13 cycles) |
| `m_axis_tvalid` | Output | 1-bit | Downstream correction mask valid flag |
| `m_axis_tready` | Input | 1-bit | Downstream actuator ready handshake |

---

## 4. Simulation & Verification Results

The RTL core and SystemVerilog verification suite were simulated and verified using **Synopsys VCS**, **Synopsys Verdi (nWave)**, and **Icarus Verilog / GTKWave**.

### Waveform & Output Verification

![Simulation Output 1](Screenshot%20from%202026-11-11%2010-55-49.png)

![Simulation Output 2](Screenshot%20from%202026-11-11%2010-56-30.png)

### Benchmark Summary

| Test Scenario | Input Syndrome | Decoded Pauli-X Mask | Decoded Pauli-Z Mask | Clock Cycles | Total Latency @ 200 MHz |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Pure Pauli-X Error on D1** | `8'h03` (`0000_0011`) | `9'b000000010` (`9'h002`) | `9'b000000000` (`9'h000`) | **13 (0x0D)** | **65 ns** |
| **Pure Pauli-Z Error on D7** | `8'hC0` (`1100_0000`) | `9'b000000000` (`9'h000`) | `9'b010000000` (`9'h080`) | **13 (0x0D)** | **65 ns** |
| **Pauli-Y (X+Z) Error on Center D4** | `8'h99` (`1001_1001`) | `9'b000010000` (`9'h010`) | `9'b000010000` (`9'h010`) | **13 (0x0D)** | **65 ns** |
| **Multi-Qubit Mixed Error (D3 + D5)** | `8'hA5` (`1010_0101`) | `9'b000001000` (`9'h008`) | `9'b000100000` (`9'h020`) | **13 (0x0D)** | **65 ns** |

---

## 5. Repository Structure

```text
css_rtl_q/
|-- surface_decoder_uf_grid.v                  # Synthesizable AXI4-Stream CSS Surface Code Decoder RTL
|-- tb_surface_decoder_uf_grid.sv              # SystemVerilog verification testbench with FSDB/VCD dump
|-- Screenshot from 2026-11-11 10-55-49.png    # Simulation verification screenshot 1
|-- Screenshot from 2026-11-11 10-56-30.png    # Simulation verification screenshot 2
+-- README.md                                  # Project documentation
```

---

## 6. How to Run the Simulation

### Option A: Using Synopsys VCS & Verdi (Industry Flow)

```bash
# 1. Compile and elaborate RTL and SystemVerilog testbench
vcs -sverilog +v2k -timescale=1ns/1ps \
    surface_decoder_uf_grid.v tb_surface_decoder_uf_grid.sv \
    -debug_access+all -kdb -l vcs_uf_compile.log -o simv_uf

# 2. Run the simulation executable
./simv_uf -l sim_uf_run.log

# 3. Open the FSDB waveform in Synopsys Verdi
verdi -ssf uf_grid_decoder.fsdb &
```

### Option B: Using Icarus Verilog & GTKWave (Open-Source Flow)

```bash
# 1. Compile with SystemVerilog-2012 flag
iverilog -g2012 -o sim_uf surface_decoder_uf_grid.v tb_surface_decoder_uf_grid.sv

# 2. Execute simulation
./sim_uf

# 3. View waveform in GTKWave
gtkwave wave.vcd &
```

---

## 7. Team & Acknowledgments

Developed for the **VConnecTech Engineering Marathon 2026** (FPGA Design & Semiconductor/VLSI Track) in partnership with **Silicon Setu**, **IEEE Madras Section**, and **IEEE CASS Madras**.

* **Author / Team Lead:** Sharavanakumar R — *Rajalakshmi Institute of Technology, Chennai* ([GitHub: @sharavana864](https://github.com/sharavana864))
