// =============================================================================
// Out-of-Order Processor Core Definitions
// =============================================================================
// File: ooo_processor_defines.vh
// Description: Global parameters and definitions for OoO processor (Verilog)
// Author: Suryaa Senthilkumar Shanthi
// Date: 8 July 2025
// =============================================================================

`ifndef OOO_PROCESSOR_DEFINES_VH
`define OOO_PROCESSOR_DEFINES_VH

// =============================================================================
// GLOBAL PARAMETERS
// =============================================================================

// Architecture Parameters
`define XLEN                32                  // Data width
`define ARCH_REGS           32                  // Number of architectural registers
`define PHYS_REGS           64                  // Number of physical registers
`define PHYS_REG_BITS       6                   // $clog2(PHYS_REGS)
`define ARCH_REG_BITS       5                   // $clog2(ARCH_REGS)

// Pipeline Parameters
`define FETCH_WIDTH         2                   // Instructions fetched per cycle
`define DECODE_WIDTH        2                   // Instructions decoded per cycle
`define ISSUE_WIDTH         2                   // Instructions issued per cycle
`define COMMIT_WIDTH        2                   // Instructions committed per cycle

// Buffer Sizes
`define ROB_SIZE            32                  // Reorder buffer entries
`define RS_SIZE             16                  // Reservation station entries
`define LOAD_QUEUE_SIZE     8                   // Load queue entries
`define STORE_QUEUE_SIZE    8                   // Store queue entries
`define FETCH_QUEUE_SIZE    8                   // Fetch queue entries
`define ROB_ADDR_BITS       5                   // $clog2(ROB_SIZE)
`define RS_ADDR_BITS        4                   // $clog2(RS_SIZE)

// Cache Parameters
`define ICACHE_SIZE         8192                // I-cache size in bytes
`define DCACHE_SIZE         8192                // D-cache size in bytes
`define CACHE_LINE_SIZE     64                  // Cache line size in bytes

// Branch Predictor Parameters
`define BTB_SIZE            256                 // Branch target buffer entries
`define BHT_SIZE            1024                // Branch history table entries

// =============================================================================
// INSTRUCTION TYPES AND OPCODES
// =============================================================================

// Instruction Types
`define INST_TYPE_R         3'b000              // Register-register
`define INST_TYPE_I         3'b001              // Immediate
`define INST_TYPE_S         3'b010              // Store
`define INST_TYPE_B         3'b011              // Branch
`define INST_TYPE_U         3'b100              // Upper immediate
`define INST_TYPE_J         3'b101              // Jump

// Execution Unit Types
`define EXEC_ALU            2'b00               // Arithmetic Logic Unit
`define EXEC_BRANCH         2'b01               // Branch Unit
`define EXEC_LOAD_STORE     2'b10               // Load/Store Unit
`define EXEC_MULT_DIV       2'b11               // Multiply/Divide Unit

// ALU Operations
`define ALU_ADD             4'b0000
`define ALU_SUB             4'b0001
`define ALU_AND             4'b0010
`define ALU_OR              4'b0011
`define ALU_XOR             4'b0100
`define ALU_SLL             4'b0101
`define ALU_SRL             4'b0110
`define ALU_SRA             4'b0111
`define ALU_SLT             4'b1000
`define ALU_SLTU            4'b1001
`define ALU_LUI             4'b1010
`define ALU_AUIPC           4'b1011

// Branch Operations
`define BR_EQ               3'b000              // Branch if equal
`define BR_NE               3'b001              // Branch if not equal
`define BR_LT               3'b100              // Branch if less than
`define BR_GE               3'b101              // Branch if greater or equal
`define BR_LTU              3'b110              // Branch if less than unsigned
`define BR_GEU              3'b111              // Branch if greater or equal unsigned
`define BR_JAL              3'b010              // Jump and link
`define BR_JALR             3'b011              // Jump and link register

// Memory Operations
`define MEM_LB              3'b000              // Load byte
`define MEM_LH              3'b001              // Load halfword
`define MEM_LW              3'b010              // Load word
`define MEM_LBU             3'b100              // Load byte unsigned
`define MEM_LHU             3'b101              // Load halfword unsigned
`define MEM_SB              3'b000              // Store byte
`define MEM_SH              3'b001              // Store halfword
`define MEM_SW              3'b010              // Store word

// =============================================================================
// RISC-V OPCODES
// =============================================================================

`define OPCODE_LUI          7'b0110111          // Load Upper Immediate
`define OPCODE_AUIPC        7'b0010111          // Add Upper Immediate to PC
`define OPCODE_JAL          7'b1101111          // Jump and Link
`define OPCODE_JALR         7'b1100111          // Jump and Link Register
`define OPCODE_BRANCH       7'b1100011          // Branch instructions
`define OPCODE_LOAD         7'b0000011          // Load instructions
`define OPCODE_STORE        7'b0100011          // Store instructions
`define OPCODE_ALU_IMM      7'b0010011          // ALU with immediate
`define OPCODE_ALU_REG      7'b0110011          // ALU with registers

// =============================================================================
// FUNCTION CODES
// =============================================================================

// ALU Immediate Function3 codes
`define FUNC3_ADDI          3'b000
`define FUNC3_SLTI          3'b010
`define FUNC3_SLTIU         3'b011
`define FUNC3_XORI          3'b100
`define FUNC3_ORI           3'b110
`define FUNC3_ANDI          3'b111
`define FUNC3_SLLI          3'b001
`define FUNC3_SRLI_SRAI     3'b101

// ALU Register Function3 codes
`define FUNC3_ADD_SUB       3'b000
`define FUNC3_SLL           3'b001
`define FUNC3_SLT           3'b010
`define FUNC3_SLTU          3'b011
`define FUNC3_XOR           3'b100
`define FUNC3_SRL_SRA       3'b101
`define FUNC3_OR            3'b110
`define FUNC3_AND           3'b111

// Branch Function3 codes
`define FUNC3_BEQ           3'b000
`define FUNC3_BNE           3'b001
`define FUNC3_BLT           3'b100
`define FUNC3_BGE           3'b101
`define FUNC3_BLTU          3'b110
`define FUNC3_BGEU          3'b111

// Load Function3 codes
`define FUNC3_LB            3'b000
`define FUNC3_LH            3'b001
`define FUNC3_LW            3'b010
`define FUNC3_LBU           3'b100
`define FUNC3_LHU           3'b101

// Store Function3 codes
`define FUNC3_SB            3'b000
`define FUNC3_SH            3'b001
`define FUNC3_SW            3'b010

// =============================================================================
// CONTROL SIGNALS
// =============================================================================

// Pipeline Control
`define PIPE_CTRL_STALL_FETCH       0
`define PIPE_CTRL_STALL_DECODE      1
`define PIPE_CTRL_STALL_RENAME      2
`define PIPE_CTRL_STALL_ISSUE       3
`define PIPE_CTRL_FLUSH_FETCH       4
`define PIPE_CTRL_FLUSH_DECODE      5
`define PIPE_CTRL_FLUSH_RENAME      6
`define PIPE_CTRL_FLUSH_ISSUE       7
`define PIPE_CTRL_FLUSH_EXECUTE     8
`define PIPE_CTRL_WIDTH             9

// Exception Codes
`define EXCEPT_NONE                 4'b0000
`define EXCEPT_INST_ADDR_MISALIGN   4'b0001
`define EXCEPT_INST_ACCESS_FAULT    4'b0010
`define EXCEPT_ILLEGAL_INST         4'b0011
`define EXCEPT_BREAKPOINT           4'b0100
`define EXCEPT_LOAD_ADDR_MISALIGN   4'b0101
`define EXCEPT_LOAD_ACCESS_FAULT    4'b0110
`define EXCEPT_STORE_ADDR_MISALIGN  4'b0111
`define EXCEPT_STORE_ACCESS_FAULT   4'b1000

// =============================================================================
// USEFUL MACROS
// =============================================================================

// Extract fields from instruction
`define GET_OPCODE(inst)    inst[6:0]
`define GET_RD(inst)        inst[11:7]
`define GET_FUNC3(inst)     inst[14:12]
`define GET_RS1(inst)       inst[19:15]
`define GET_RS2(inst)       inst[24:20]
`define GET_FUNC7(inst)     inst[31:25]

// Immediate extraction macros
`define GET_I_IMM(inst)     {{20{inst[31]}}, inst[31:20]}
`define GET_S_IMM(inst)     {{20{inst[31]}}, inst[31:25], inst[11:7]}
`define GET_B_IMM(inst)     {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
`define GET_U_IMM(inst)     {inst[31:12], 12'b0}
`define GET_J_IMM(inst)     {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}

// Check if register is zero
`define IS_REG_ZERO(reg)    (reg == 5'b00000)

// =============================================================================
// STRUCTURE SIZES (for wire/reg declarations)
// =============================================================================

// Instruction structure size
`define DECODED_INST_SIZE   (`XLEN + `XLEN + 5 + 5 + 5 + `XLEN + 3 + 2 + 4 + 3 + 3 + 1)

// ROB entry structure size  
`define ROB_ENTRY_SIZE      (5 + `PHYS_REG_BITS + `XLEN + `XLEN + 1 + 1 + 1 + 4 + 1 + `XLEN)

// Reservation station entry size
`define RS_ENTRY_SIZE       (`DECODED_INST_SIZE + `XLEN + `XLEN + 1 + 1 + `PHYS_REG_BITS + `PHYS_REG_BITS + `PHYS_REG_BITS + `ROB_ADDR_BITS + 1 + 1)

// RAT entry size
`define RAT_ENTRY_SIZE      (`PHYS_REG_BITS + 1)

`endif // OOO_PROCESSOR_DEFINES_VH