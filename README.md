# Superscalar-Pipeline-in-Verilog
## Module Descriptions

### Core Pipeline Modules (`rtl/core/`)

#### `ooo_processor_defines.vh`
Global parameter definitions including:
- Architecture parameters (register counts, pipeline widths)
- Buffer sizes (ROB, reservation station, queues)
- Instruction type encodings and operation codes
- RISC-V opcode and function code definitions
- Utility macros for instruction field extraction

#### `register_file.v`
**Modules**: `register_file`, `free_list_manager`
- Multi-ported physical register file (4 read, 2 write ports)
- Register ready bit tracking for dependency resolution
- Free list management for physical register allocation/deallocation
- Supports register renaming with expanded physical register space

#### `rename_unit.v`
**Modules**: `register_alias_table`, `rename_stage`
- Register Alias Table (RAT) mapping architectural to physical registers
- Speculative and architectural state maintenance
- Register renaming pipeline stage with hazard detection
- Interfaces with ROB and free list for resource allocation

#### `reorder_buffer.v`
**Modules**: `rob_controller`, `commit_stage`
- Reorder Buffer (ROB) for maintaining program order
- In-order commit logic ensuring precise architectural state
- Exception handling and branch misprediction recovery
- Performance monitoring with instruction/cycle counting

#### `fetch_unit.v`
**Modules**: `instruction_fetch`, `branch_predictor`, `fetch_queue`
- Superscalar instruction fetch (2 instructions per cycle)
- 2-bit saturating counter branch predictor with BTB
- Fetch queue for decoupling frontend from backend
- PC management and branch target calculation

#### `decode_unit.v`
**Modules**: `instruction_decoder`, `decode_stage`
- Complete RISC-V instruction decoder supporting RV32I
- Control signal generation for execution units
- Immediate value extraction and sign extension
- Illegal instruction detection and exception generation

#### `reservation_station.v`
**Modules**: `rs_controller`, `instruction_scheduler`
- Dynamic instruction scheduling with age-based priority
- Operand dependency tracking and wakeup logic
- Multi-port register file interface management
- Resource allocation and conflict resolution

#### `execution_units.v`
**Modules**: `alu_unit`, `branch_unit`, `load_store_unit`
- **ALU Unit**: All arithmetic/logical operations with overflow detection
- **Branch Unit**: Branch condition evaluation and misprediction detection
- **Load/Store Unit**: Memory operations with alignment checking
- Result forwarding and bypass network interfaces

#### `pipeline_controller.v`
**Modules**: `hazard_detection`, `pipeline_flush`, `stall_controller`
- Comprehensive hazard detection (structural, data, control)
- Pipeline stall and flush coordination
- Branch misprediction and exception recovery management
- Performance monitoring and bottleneck analysis

### Top-Level Integration

#### `ooo_processor_top.v`
**Module**: `ooo_processor_top`
- Complete processor integration connecting all pipeline stages
- External memory interface (instruction and data)
- Global control signal distribution
- Debug and performance monitoring interfaces
- Clock domain and reset management

### Verification (`testbench/`)

#### `tb_ooo_processor.v`
**Module**: `tb_ooo_processor`
- Comprehensive testbench with 5 different test programs
- Simple memory models for instruction and data memory
- Performance monitoring and IPC calculation
- Automatic test execution with timeout protection
- Waveform generation for debugging

## Test Programs

1. **Simple ALU Test** - Basic arithmetic and logical operations
2. **Load/Store Test** - Memory operation verification
3. **Branch Test** - Conditional branch and jump instructions
4. **Data Dependency Test** - RAW dependency handling
5. **Comprehensive Test** - Mixed instruction types and complex dependencies

## Tools and Requirements

- **Xilinx Vivado 2020.2** or later
- **Verilog-2001** compatible synthesis tools
