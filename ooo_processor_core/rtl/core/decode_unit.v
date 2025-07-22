// =============================================================================
// Instruction Decode Unit
// =============================================================================
// File: decode_unit.v
// Description: Instruction decoder and decode pipeline stage
// Author: Suryaa Senthilkumar Shanthi
// Date: 16 July 2025
// =============================================================================

`include "ooo_processor_defines.vh"

// =============================================================================
// Instruction Decoder
// =============================================================================
// Decodes RISC-V instructions and generates control signals

module instruction_decoder (
    // Input instruction
    input wire [31:0] instruction,
    input wire [`XLEN-1:0] pc,
    input wire valid,
    
    // Decoded instruction fields
    output wire [6:0] opcode,
    output wire [4:0] rd,
    output wire [2:0] func3,
    output wire [4:0] rs1,
    output wire [4:0] rs2,
    output wire [6:0] func7,
    output wire [31:0] immediate,
    
    // Control signals
    output wire [2:0] inst_type,
    output wire [1:0] exec_unit,
    output wire [3:0] alu_op,
    output wire [2:0] branch_op,
    output wire [2:0] mem_op,
    output wire uses_rs1,
    output wire uses_rs2,
    output wire writes_rd,
    output wire is_branch,
    output wire is_jump,
    output wire is_load,
    output wire is_store,
    output wire is_alu_imm,
    output wire is_alu_reg,
    output wire is_lui,
    output wire is_auipc,
    output wire illegal_instruction,
    
    // Pipeline control
    output wire decoder_ready
);

    // =============================================================================
    // Instruction Field Extraction
    // =============================================================================
    
    assign opcode = instruction[6:0];
    assign rd = instruction[11:7];
    assign func3 = instruction[14:12];
    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];
    assign func7 = instruction[31:25];
    
    // =============================================================================
    // Instruction Type Detection
    // =============================================================================
    
    wire is_r_type, is_i_type, is_s_type, is_b_type, is_u_type, is_j_type;
    
    assign is_r_type = (opcode == `OPCODE_ALU_REG);
    assign is_i_type = (opcode == `OPCODE_ALU_IMM) || (opcode == `OPCODE_LOAD) || (opcode == `OPCODE_JALR);
    assign is_s_type = (opcode == `OPCODE_STORE);
    assign is_b_type = (opcode == `OPCODE_BRANCH);
    assign is_u_type = (opcode == `OPCODE_LUI) || (opcode == `OPCODE_AUIPC);
    assign is_j_type = (opcode == `OPCODE_JAL);
    
    // =============================================================================
    // Immediate Generation
    // =============================================================================
    
    reg [31:0] imm_value;
    
    always @(*) begin
        case (1'b1)
            is_i_type: imm_value = `GET_I_IMM(instruction);
            is_s_type: imm_value = `GET_S_IMM(instruction);
            is_b_type: imm_value = `GET_B_IMM(instruction);
            is_u_type: imm_value = `GET_U_IMM(instruction);
            is_j_type: imm_value = `GET_J_IMM(instruction);
            default:   imm_value = 32'b0;
        endcase
    end
    
    assign immediate = imm_value;
    
    // =============================================================================
    // Instruction Type Encoding
    // =============================================================================
    
    reg [2:0] instruction_type;
    
    always @(*) begin
        case (1'b1)
            is_r_type: instruction_type = `INST_TYPE_R;
            is_i_type: instruction_type = `INST_TYPE_I;
            is_s_type: instruction_type = `INST_TYPE_S;
            is_b_type: instruction_type = `INST_TYPE_B;
            is_u_type: instruction_type = `INST_TYPE_U;
            is_j_type: instruction_type = `INST_TYPE_J;
            default:   instruction_type = 3'b111;  // Invalid
        endcase
    end
    
    assign inst_type = instruction_type;
    
    // =============================================================================
    // Execution Unit Assignment
    // =============================================================================
    
    reg [1:0] execution_unit;
    
    always @(*) begin
        case (opcode)
            `OPCODE_ALU_REG, `OPCODE_ALU_IMM, `OPCODE_LUI, `OPCODE_AUIPC: begin
                execution_unit = `EXEC_ALU;
            end
            `OPCODE_BRANCH, `OPCODE_JAL, `OPCODE_JALR: begin
                execution_unit = `EXEC_BRANCH;
            end
            `OPCODE_LOAD, `OPCODE_STORE: begin
                execution_unit = `EXEC_LOAD_STORE;
            end
            default: begin
                execution_unit = `EXEC_ALU;  // Default to ALU
            end
        endcase
    end
    
    assign exec_unit = execution_unit;
    
    // =============================================================================
    // ALU Operation Decoding
    // =============================================================================
    
    reg [3:0] alu_operation;
    
    always @(*) begin
        case (opcode)
            `OPCODE_ALU_IMM: begin
                case (func3)
                    `FUNC3_ADDI:        alu_operation = `ALU_ADD;
                    `FUNC3_SLTI:        alu_operation = `ALU_SLT;
                    `FUNC3_SLTIU:       alu_operation = `ALU_SLTU;
                    `FUNC3_XORI:        alu_operation = `ALU_XOR;
                    `FUNC3_ORI:         alu_operation = `ALU_OR;
                    `FUNC3_ANDI:        alu_operation = `ALU_AND;
                    `FUNC3_SLLI:        alu_operation = `ALU_SLL;
                    `FUNC3_SRLI_SRAI:   alu_operation = func7[5] ? `ALU_SRA : `ALU_SRL;
                    default:            alu_operation = `ALU_ADD;
                endcase
            end
            `OPCODE_ALU_REG: begin
                case (func3)
                    `FUNC3_ADD_SUB:     alu_operation = func7[5] ? `ALU_SUB : `ALU_ADD;
                    `FUNC3_SLL:         alu_operation = `ALU_SLL;
                    `FUNC3_SLT:         alu_operation = `ALU_SLT;
                    `FUNC3_SLTU:        alu_operation = `ALU_SLTU;
                    `FUNC3_XOR:         alu_operation = `ALU_XOR;
                    `FUNC3_SRL_SRA:     alu_operation = func7[5] ? `ALU_SRA : `ALU_SRL;
                    `FUNC3_OR:          alu_operation = `ALU_OR;
                    `FUNC3_AND:         alu_operation = `ALU_AND;
                    default:            alu_operation = `ALU_ADD;
                endcase
            end
            `OPCODE_LUI:    alu_operation = `ALU_LUI;
            `OPCODE_AUIPC:  alu_operation = `ALU_AUIPC;
            default:        alu_operation = `ALU_ADD;
        endcase
    end
    
    assign alu_op = alu_operation;
    
    // =============================================================================
    // Branch Operation Decoding
    // =============================================================================
    
    reg [2:0] branch_operation;
    
    always @(*) begin
        case (opcode)
            `OPCODE_BRANCH: begin
                case (func3)
                    `FUNC3_BEQ:     branch_operation = `BR_EQ;
                    `FUNC3_BNE:     branch_operation = `BR_NE;
                    `FUNC3_BLT:     branch_operation = `BR_LT;
                    `FUNC3_BGE:     branch_operation = `BR_GE;
                    `FUNC3_BLTU:    branch_operation = `BR_LTU;
                    `FUNC3_BGEU:    branch_operation = `BR_GEU;
                    default:        branch_operation = `BR_EQ;
                endcase
            end
            `OPCODE_JAL:    branch_operation = `BR_JAL;
            `OPCODE_JALR:   branch_operation = `BR_JALR;
            default:        branch_operation = 3'b000;
        endcase
    end
    
    assign branch_op = branch_operation;
    
    // =============================================================================
    // Memory Operation Decoding
    // =============================================================================
    
    reg [2:0] memory_operation;
    
    always @(*) begin
        case (opcode)
            `OPCODE_LOAD: begin
                case (func3)
                    `FUNC3_LB:      memory_operation = `MEM_LB;
                    `FUNC3_LH:      memory_operation = `MEM_LH;
                    `FUNC3_LW:      memory_operation = `MEM_LW;
                    `FUNC3_LBU:     memory_operation = `MEM_LBU;
                    `FUNC3_LHU:     memory_operation = `MEM_LHU;
                    default:        memory_operation = `MEM_LW;
                endcase
            end
            `OPCODE_STORE: begin
                case (func3)
                    `FUNC3_SB:      memory_operation = `MEM_SB;
                    `FUNC3_SH:      memory_operation = `MEM_SH;
                    `FUNC3_SW:      memory_operation = `MEM_SW;
                    default:        memory_operation = `MEM_SW;
                endcase
            end
            default: memory_operation = 3'b000;
        endcase
    end
    
    assign mem_op = memory_operation;
    
    // =============================================================================
    // Register Usage Detection
    // =============================================================================
    
    assign uses_rs1 = is_r_type || is_i_type || is_s_type || is_b_type ||
                     (opcode == `OPCODE_AUIPC);
    
    assign uses_rs2 = is_r_type || is_s_type || is_b_type;
    
    assign writes_rd = is_r_type || is_i_type || is_u_type || is_j_type ||
                      (opcode == `OPCODE_AUIPC);
    
    // =============================================================================
    // Instruction Category Flags
    // =============================================================================
    
    assign is_branch = (opcode == `OPCODE_BRANCH);
    assign is_jump = (opcode == `OPCODE_JAL) || (opcode == `OPCODE_JALR);
    assign is_load = (opcode == `OPCODE_LOAD);
    assign is_store = (opcode == `OPCODE_STORE);
    assign is_alu_imm = (opcode == `OPCODE_ALU_IMM);
    assign is_alu_reg = (opcode == `OPCODE_ALU_REG);
    assign is_lui = (opcode == `OPCODE_LUI);
    assign is_auipc = (opcode == `OPCODE_AUIPC);
    
    // =============================================================================
    // Illegal Instruction Detection
    // =============================================================================
    
    wire valid_opcode;
    wire valid_func3;
    wire valid_func7;
    
    assign valid_opcode = (opcode == `OPCODE_LUI) || (opcode == `OPCODE_AUIPC) ||
                         (opcode == `OPCODE_JAL) || (opcode == `OPCODE_JALR) ||
                         (opcode == `OPCODE_BRANCH) || (opcode == `OPCODE_LOAD) ||
                         (opcode == `OPCODE_STORE) || (opcode == `OPCODE_ALU_IMM) ||
                         (opcode == `OPCODE_ALU_REG);
    
    // Simplified func3 validation
    assign valid_func3 = 1'b1;  // Can be enhanced for specific validation
    
    // Simplified func7 validation for R-type instructions
    assign valid_func7 = (opcode != `OPCODE_ALU_REG) || 
                        (func7 == 7'b0000000) || (func7 == 7'b0100000);
    
    assign illegal_instruction = valid && (!valid_opcode || !valid_func3 || !valid_func7);
    
    // =============================================================================
    // Ready Signal
    // =============================================================================
    
    assign decoder_ready = 1'b1;  // Decoder is always ready (combinational)

endmodule

// =============================================================================
// Decode Stage
// =============================================================================
// Pipeline stage that coordinates instruction decoding and hazard detection

module decode_stage (
    input wire clk,
    input wire rst_n,
    
    // Input from fetch queue
    input wire [`XLEN-1:0] fetch_pc1,
    input wire [`XLEN-1:0] fetch_pc2,
    input wire [31:0] fetch_instruction1,
    input wire [31:0] fetch_instruction2,
    input wire fetch_valid1,
    input wire fetch_valid2,
    input wire fetch_predicted_taken1,
    input wire fetch_predicted_taken2,
    input wire [`XLEN-1:0] fetch_predicted_target1,
    input wire [`XLEN-1:0] fetch_predicted_target2,
    
    // Output to rename stage
    output reg [`XLEN-1:0] decode_pc1,
    output reg [`XLEN-1:0] decode_pc2,
    output reg [31:0] decode_instruction1,
    output reg [31:0] decode_instruction2,
    output reg [4:0] decode_rs1_1,
    output reg [4:0] decode_rs2_1,
    output reg [4:0] decode_rd_1,
    output reg [4:0] decode_rs1_2,
    output reg [4:0] decode_rs2_2,
    output reg [4:0] decode_rd_2,
    output reg [31:0] decode_immediate1,
    output reg [31:0] decode_immediate2,
    output reg [2:0] decode_inst_type1,
    output reg [2:0] decode_inst_type2,
    output reg [1:0] decode_exec_unit1,
    output reg [1:0] decode_exec_unit2,
    output reg [3:0] decode_alu_op1,
    output reg [3:0] decode_alu_op2,
    output reg [2:0] decode_branch_op1,
    output reg [2:0] decode_branch_op2,
    output reg [2:0] decode_mem_op1,
    output reg [2:0] decode_mem_op2,
    output reg decode_uses_rs1_1,
    output reg decode_uses_rs2_1,
    output reg decode_writes_rd_1,
    output reg decode_uses_rs1_2,
    output reg decode_uses_rs2_2,
    output reg decode_writes_rd_2,
    output reg decode_is_branch1,
    output reg decode_is_branch2,
    output reg decode_is_jump1,
    output reg decode_is_jump2,
    output reg decode_is_load1,
    output reg decode_is_load2,
    output reg decode_is_store1,
    output reg decode_is_store2,
    output reg decode_predicted_taken1,
    output reg decode_predicted_taken2,
    output reg [`XLEN-1:0] decode_predicted_target1,
    output reg [`XLEN-1:0] decode_predicted_target2,
    output reg decode_valid1,
    output reg decode_valid2,
    
    // Exception interface
    output reg decode_exception1,
    output reg decode_exception2,
    output reg [3:0] decode_exception_code1,
    output reg [3:0] decode_exception_code2,
    
    // Pipeline control
    input wire stall_decode,
    input wire flush_decode,
    output wire decode_stall_req,
    
    // Flow control
    input wire rename_ready,
    output wire fetch_ready
);

    // =============================================================================
    // Decoder Instances
    // =============================================================================
    
    // Decoder for instruction 1
    wire [6:0] dec1_opcode;
    wire [4:0] dec1_rd, dec1_rs1, dec1_rs2;
    wire [2:0] dec1_func3;
    wire [6:0] dec1_func7;
    wire [31:0] dec1_immediate;
    wire [2:0] dec1_inst_type;
    wire [1:0] dec1_exec_unit;
    wire [3:0] dec1_alu_op;
    wire [2:0] dec1_branch_op;
    wire [2:0] dec1_mem_op;
    wire dec1_uses_rs1, dec1_uses_rs2, dec1_writes_rd;
    wire dec1_is_branch, dec1_is_jump, dec1_is_load, dec1_is_store;
    wire dec1_is_alu_imm, dec1_is_alu_reg, dec1_is_lui, dec1_is_auipc;
    wire dec1_illegal_instruction;
    wire dec1_ready;
    
    instruction_decoder decoder1 (
        .instruction(fetch_instruction1),
        .pc(fetch_pc1),
        .valid(fetch_valid1),
        .opcode(dec1_opcode),
        .rd(dec1_rd),
        .func3(dec1_func3),
        .rs1(dec1_rs1),
        .rs2(dec1_rs2),
        .func7(dec1_func7),
        .immediate(dec1_immediate),
        .inst_type(dec1_inst_type),
        .exec_unit(dec1_exec_unit),
        .alu_op(dec1_alu_op),
        .branch_op(dec1_branch_op),
        .mem_op(dec1_mem_op),
        .uses_rs1(dec1_uses_rs1),
        .uses_rs2(dec1_uses_rs2),
        .writes_rd(dec1_writes_rd),
        .is_branch(dec1_is_branch),
        .is_jump(dec1_is_jump),
        .is_load(dec1_is_load),
        .is_store(dec1_is_store),
        .is_alu_imm(dec1_is_alu_imm),
        .is_alu_reg(dec1_is_alu_reg),
        .is_lui(dec1_is_lui),
        .is_auipc(dec1_is_auipc),
        .illegal_instruction(dec1_illegal_instruction),
        .decoder_ready(dec1_ready)
    );
    
    // Decoder for instruction 2
    wire [6:0] dec2_opcode;
    wire [4:0] dec2_rd, dec2_rs1, dec2_rs2;
    wire [2:0] dec2_func3;
    wire [6:0] dec2_func7;
    wire [31:0] dec2_immediate;
    wire [2:0] dec2_inst_type;
    wire [1:0] dec2_exec_unit;
    wire [3:0] dec2_alu_op;
    wire [2:0] dec2_branch_op;
    wire [2:0] dec2_mem_op;
    wire dec2_uses_rs1, dec2_uses_rs2, dec2_writes_rd;
    wire dec2_is_branch, dec2_is_jump, dec2_is_load, dec2_is_store;
    wire dec2_is_alu_imm, dec2_is_alu_reg, dec2_is_lui, dec2_is_auipc;
    wire dec2_illegal_instruction;
    wire dec2_ready;
    
    instruction_decoder decoder2 (
        .instruction(fetch_instruction2),
        .pc(fetch_pc2),
        .valid(fetch_valid2),
        .opcode(dec2_opcode),
        .rd(dec2_rd),
        .func3(dec2_func3),
        .rs1(dec2_rs1),
        .rs2(dec2_rs2),
        .func7(dec2_func7),
        .immediate(dec2_immediate),
        .inst_type(dec2_inst_type),
        .exec_unit(dec2_exec_unit),
        .alu_op(dec2_alu_op),
        .branch_op(dec2_branch_op),
        .mem_op(dec2_mem_op),
        .uses_rs1(dec2_uses_rs1),
        .uses_rs2(dec2_uses_rs2),
        .writes_rd(dec2_writes_rd),
        .is_branch(dec2_is_branch),
        .is_jump(dec2_is_jump),
        .is_load(dec2_is_load),
        .is_store(dec2_is_store),
        .is_alu_imm(dec2_is_alu_imm),
        .is_alu_reg(dec2_is_alu_reg),
        .is_lui(dec2_is_lui),
        .is_auipc(dec2_is_auipc),
        .illegal_instruction(dec2_illegal_instruction),
        .decoder_ready(dec2_ready)
    );
    
    // =============================================================================
    // Hazard Detection
    // =============================================================================
    
    wire structural_hazard;
    wire decode_hazard;
    
    // Structural hazard: both instructions trying to use same execution unit
    assign structural_hazard = fetch_valid1 && fetch_valid2 && 
                              (dec1_exec_unit == dec2_exec_unit) &&
                              (dec1_exec_unit == `EXEC_LOAD_STORE);  // Only LSU has structural hazards
    
    // Decode hazard: illegal instructions
    assign decode_hazard = (fetch_valid1 && dec1_illegal_instruction) ||
                          (fetch_valid2 && dec2_illegal_instruction);
    
    // =============================================================================
    // Flow Control
    // =============================================================================
    
    assign decode_stall_req = structural_hazard || decode_hazard || !rename_ready;
    assign fetch_ready = !stall_decode && rename_ready;
    
    // =============================================================================
    // Pipeline Register
    // =============================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all outputs
            decode_pc1 <= {`XLEN{1'b0}};
            decode_pc2 <= {`XLEN{1'b0}};
            decode_instruction1 <= 32'b0;
            decode_instruction2 <= 32'b0;
            decode_rs1_1 <= 5'b0;
            decode_rs2_1 <= 5'b0;
            decode_rd_1 <= 5'b0;
            decode_rs1_2 <= 5'b0;
            decode_rs2_2 <= 5'b0;
            decode_rd_2 <= 5'b0;
            decode_immediate1 <= 32'b0;
            decode_immediate2 <= 32'b0;
            decode_inst_type1 <= 3'b0;
            decode_inst_type2 <= 3'b0;
            decode_exec_unit1 <= 2'b0;
            decode_exec_unit2 <= 2'b0;
            decode_alu_op1 <= 4'b0;
            decode_alu_op2 <= 4'b0;
            decode_branch_op1 <= 3'b0;
            decode_branch_op2 <= 3'b0;
            decode_mem_op1 <= 3'b0;
            decode_mem_op2 <= 3'b0;
            decode_uses_rs1_1 <= 1'b0;
            decode_uses_rs2_1 <= 1'b0;
            decode_writes_rd_1 <= 1'b0;
            decode_uses_rs1_2 <= 1'b0;
            decode_uses_rs2_2 <= 1'b0;
            decode_writes_rd_2 <= 1'b0;
            decode_is_branch1 <= 1'b0;
            decode_is_branch2 <= 1'b0;
            decode_is_jump1 <= 1'b0;
            decode_is_jump2 <= 1'b0;
            decode_is_load1 <= 1'b0;
            decode_is_load2 <= 1'b0;
            decode_is_store1 <= 1'b0;
            decode_is_store2 <= 1'b0;
            decode_predicted_taken1 <= 1'b0;
            decode_predicted_taken2 <= 1'b0;
            decode_predicted_target1 <= {`XLEN{1'b0}};
            decode_predicted_target2 <= {`XLEN{1'b0}};
            decode_valid1 <= 1'b0;
            decode_valid2 <= 1'b0;
            decode_exception1 <= 1'b0;
            decode_exception2 <= 1'b0;
            decode_exception_code1 <= 4'b0;
            decode_exception_code2 <= 4'b0;
        end
        else if (flush_decode) begin
            // Flush pipeline stage
            decode_valid1 <= 1'b0;
            decode_valid2 <= 1'b0;
            decode_exception1 <= 1'b0;
            decode_exception2 <= 1'b0;
        end
        else if (!stall_decode && rename_ready && !decode_stall_req) begin
            // Normal operation - process instructions
            
            // Instruction 1
            decode_pc1 <= fetch_pc1;
            decode_instruction1 <= fetch_instruction1;
            decode_rs1_1 <= dec1_rs1;
            decode_rs2_1 <= dec1_rs2;
            decode_rd_1 <= dec1_rd;
            decode_immediate1 <= dec1_immediate;
            decode_inst_type1 <= dec1_inst_type;
            decode_exec_unit1 <= dec1_exec_unit;
            decode_alu_op1 <= dec1_alu_op;
            decode_branch_op1 <= dec1_branch_op;
            decode_mem_op1 <= dec1_mem_op;
            decode_uses_rs1_1 <= dec1_uses_rs1;
            decode_uses_rs2_1 <= dec1_uses_rs2;
            decode_writes_rd_1 <= dec1_writes_rd;
            decode_is_branch1 <= dec1_is_branch;
            decode_is_jump1 <= dec1_is_jump;
            decode_is_load1 <= dec1_is_load;
            decode_is_store1 <= dec1_is_store;
            decode_predicted_taken1 <= fetch_predicted_taken1;
            decode_predicted_target1 <= fetch_predicted_target1;
            decode_valid1 <= fetch_valid1 && !structural_hazard;
            decode_exception1 <= dec1_illegal_instruction;
            decode_exception_code1 <= dec1_illegal_instruction ? `EXCEPT_ILLEGAL_INST : `EXCEPT_NONE;
            
            // Instruction 2
            decode_pc2 <= fetch_pc2;
            decode_instruction2 <= fetch_instruction2;
            decode_rs1_2 <= dec2_rs1;
            decode_rs2_2 <= dec2_rs2;
            decode_rd_2 <= dec2_rd;
            decode_immediate2 <= dec2_immediate;
            decode_inst_type2 <= dec2_inst_type;
            decode_exec_unit2 <= dec2_exec_unit;
            decode_alu_op2 <= dec2_alu_op;
            decode_branch_op2 <= dec2_branch_op;
            decode_mem_op2 <= dec2_mem_op;
            decode_uses_rs1_2 <= dec2_uses_rs1;
            decode_uses_rs2_2 <= dec2_uses_rs2;
            decode_writes_rd_2 <= dec2_writes_rd;
            decode_is_branch2 <= dec2_is_branch;
            decode_is_jump2 <= dec2_is_jump;
            decode_is_load2 <= dec2_is_load;
            decode_is_store2 <= dec2_is_store;
            decode_predicted_taken2 <= fetch_predicted_taken2;
            decode_predicted_target2 <= fetch_predicted_target2;
            decode_valid2 <= fetch_valid2 && !structural_hazard;
            decode_exception2 <= dec2_illegal_instruction;
            decode_exception_code2 <= dec2_illegal_instruction ? `EXCEPT_ILLEGAL_INST : `EXCEPT_NONE;
        end
        // If stalled, maintain current outputs
    end

endmodule
