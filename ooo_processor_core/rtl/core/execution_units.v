// =============================================================================
// Execution Units
// =============================================================================
// File: execution_units.v
// Description: ALU, Branch Unit, and Load/Store Unit for OoO processor
// Author: Suryaa Senthilkumar Shanthi
// Date: 16 July 2025
// =============================================================================

`include "ooo_processor_defines.vh"

// =============================================================================
// ALU Unit
// =============================================================================
// Arithmetic Logic Unit for integer operations

module alu_unit (
    input wire clk,
    input wire rst_n,
    
    // Input from reservation station
    input wire [`XLEN-1:0] alu_pc,
    input wire [31:0] alu_instruction,
    input wire [`XLEN-1:0] alu_operand1,
    input wire [`XLEN-1:0] alu_operand2,
    input wire [31:0] alu_immediate,
    input wire [`PHYS_REG_BITS-1:0] alu_phys_rd,
    input wire [4:0] alu_arch_rd,
    input wire [3:0] alu_op,
    input wire [2:0] alu_inst_type,
    input wire [`ROB_ADDR_BITS-1:0] alu_rob_id,
    input wire alu_valid,
    
    // Output to ROB and bypass network
    output reg [`XLEN-1:0] alu_result_pc,
    output reg [31:0] alu_result_instruction,
    output reg [`XLEN-1:0] alu_result,
    output reg [`PHYS_REG_BITS-1:0] alu_result_phys_rd,
    output reg [4:0] alu_result_arch_rd,
    output reg [`ROB_ADDR_BITS-1:0] alu_result_rob_id,
    output reg alu_result_valid,
    output reg alu_exception,
    output reg [3:0] alu_exception_code,
    
    // Bypass/forwarding output
    output wire [`PHYS_REG_BITS-1:0] alu_bypass_tag,
    output wire [`XLEN-1:0] alu_bypass_data,
    output wire alu_bypass_valid,
    
    // Pipeline control
    input wire stall_alu,
    input wire flush_alu
);

    // =============================================================================
    // ALU Operation Logic
    // =============================================================================
    
    reg [`XLEN-1:0] alu_computation_result;
    reg alu_overflow;
    reg alu_computation_exception;
    
    // Operand selection (immediate vs register)
    wire [`XLEN-1:0] operand_a, operand_b;
    assign operand_a = alu_operand1;
    assign operand_b = (alu_inst_type == `INST_TYPE_I || alu_inst_type == `INST_TYPE_U) ? 
                      alu_immediate : alu_operand2;
    
    // Arithmetic operations
    wire [`XLEN:0] add_result;
    wire [`XLEN:0] sub_result;
    wire signed [`XLEN-1:0] signed_a, signed_b;
    wire [`XLEN-1:0] shift_amount;
    
    assign add_result = operand_a + operand_b;
    assign sub_result = operand_a - operand_b;
    assign signed_a = operand_a;
    assign signed_b = operand_b;
    assign shift_amount = operand_b[4:0];  // Only lower 5 bits for shift amount
    
    always @(*) begin
        alu_computation_result = {`XLEN{1'b0}};
        alu_overflow = 1'b0;
        alu_computation_exception = 1'b0;
        
        case (alu_op)
            `ALU_ADD: begin
                alu_computation_result = add_result[`XLEN-1:0];
                alu_overflow = add_result[`XLEN];
            end
            
            `ALU_SUB: begin
                alu_computation_result = sub_result[`XLEN-1:0];
                alu_overflow = sub_result[`XLEN];
            end
            
            `ALU_AND: begin
                alu_computation_result = operand_a & operand_b;
            end
            
            `ALU_OR: begin
                alu_computation_result = operand_a | operand_b;
            end
            
            `ALU_XOR: begin
                alu_computation_result = operand_a ^ operand_b;
            end
            
            `ALU_SLL: begin
                alu_computation_result = operand_a << shift_amount;
            end
            
            `ALU_SRL: begin
                alu_computation_result = operand_a >> shift_amount;
            end
            
            `ALU_SRA: begin
                alu_computation_result = signed_a >>> shift_amount;
            end
            
            `ALU_SLT: begin
                alu_computation_result = (signed_a < signed_b) ? 32'h00000001 : 32'h00000000;
            end
            
            `ALU_SLTU: begin
                alu_computation_result = (operand_a < operand_b) ? 32'h00000001 : 32'h00000000;
            end
            
            `ALU_LUI: begin
                alu_computation_result = alu_immediate;
            end
            
            `ALU_AUIPC: begin
                alu_computation_result = alu_pc + alu_immediate;
            end
            
            default: begin
                alu_computation_result = {`XLEN{1'b0}};
                alu_computation_exception = 1'b1;
            end
        endcase
    end
    
    // =============================================================================
    // Pipeline Register and Output Logic
    // =============================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_pc <= {`XLEN{1'b0}};
            alu_result_instruction <= 32'b0;
            alu_result <= {`XLEN{1'b0}};
            alu_result_phys_rd <= {`PHYS_REG_BITS{1'b0}};
            alu_result_arch_rd <= 5'b0;
            alu_result_rob_id <= {`ROB_ADDR_BITS{1'b0}};
            alu_result_valid <= 1'b0;
            alu_exception <= 1'b0;
            alu_exception_code <= 4'b0;
        end
        else if (flush_alu) begin
            alu_result_valid <= 1'b0;
            alu_exception <= 1'b0;
        end
        else if (!stall_alu) begin
            alu_result_pc <= alu_pc;
            alu_result_instruction <= alu_instruction;
            alu_result <= alu_computation_result;
            alu_result_phys_rd <= alu_phys_rd;
            alu_result_arch_rd <= alu_arch_rd;
            alu_result_rob_id <= alu_rob_id;
            alu_result_valid <= alu_valid;
            alu_exception <= alu_computation_exception;
            alu_exception_code <= alu_computation_exception ? `EXCEPT_ILLEGAL_INST : `EXCEPT_NONE;
        end
    end
    
    // =============================================================================
    // Bypass/Forwarding Interface
    // =============================================================================
    
    assign alu_bypass_tag = alu_result_phys_rd;
    assign alu_bypass_data = alu_result;
    assign alu_bypass_valid = alu_result_valid && !alu_exception;

endmodule

// =============================================================================
// Branch Unit
// =============================================================================
// Handles branch resolution and jump operations

module branch_unit (
    input wire clk,
    input wire rst_n,
    
    // Input from reservation station
    input wire [`XLEN-1:0] branch_pc,
    input wire [31:0] branch_instruction,
    input wire [`XLEN-1:0] branch_operand1,
    input wire [`XLEN-1:0] branch_operand2,
    input wire [31:0] branch_immediate,
    input wire [`PHYS_REG_BITS-1:0] branch_phys_rd,
    input wire [4:0] branch_arch_rd,
    input wire [2:0] branch_op,
    input wire [`ROB_ADDR_BITS-1:0] branch_rob_id,
    input wire branch_predicted_taken,
    input wire [`XLEN-1:0] branch_predicted_target,
    input wire branch_valid,
    
    // Output to ROB
    output reg [`XLEN-1:0] branch_result_pc,
    output reg [31:0] branch_result_instruction,
    output reg [`XLEN-1:0] branch_result,
    output reg [`PHYS_REG_BITS-1:0] branch_result_phys_rd,
    output reg [4:0] branch_result_arch_rd,
    output reg [`ROB_ADDR_BITS-1:0] branch_result_rob_id,
    output reg branch_result_valid,
    output reg branch_taken,
    output reg [`XLEN-1:0] branch_target,
    output reg branch_mispredicted,
    output reg branch_exception,
    output reg [3:0] branch_exception_code,
    
    // Bypass/forwarding output
    output wire [`PHYS_REG_BITS-1:0] branch_bypass_tag,
    output wire [`XLEN-1:0] branch_bypass_data,
    output wire branch_bypass_valid,
    
    // Pipeline control
    input wire stall_branch,
    input wire flush_branch
);

    // =============================================================================
    // Branch Condition Evaluation
    // =============================================================================
    
    reg branch_condition_met;
    reg [`XLEN-1:0] computed_target;
    reg [`XLEN-1:0] link_address;
    reg branch_computation_exception;
    
    wire signed [`XLEN-1:0] signed_op1, signed_op2;
    assign signed_op1 = branch_operand1;
    assign signed_op2 = branch_operand2;
    
    always @(*) begin
        branch_condition_met = 1'b0;
        computed_target = {`XLEN{1'b0}};
        link_address = branch_pc + 4;
        branch_computation_exception = 1'b0;
        
        case (branch_op)
            `BR_EQ: begin
                branch_condition_met = (branch_operand1 == branch_operand2);
                computed_target = branch_pc + branch_immediate;
            end
            
            `BR_NE: begin
                branch_condition_met = (branch_operand1 != branch_operand2);
                computed_target = branch_pc + branch_immediate;
            end
            
            `BR_LT: begin
                branch_condition_met = (signed_op1 < signed_op2);
                computed_target = branch_pc + branch_immediate;
            end
            
            `BR_GE: begin
                branch_condition_met = (signed_op1 >= signed_op2);
                computed_target = branch_pc + branch_immediate;
            end
            
            `BR_LTU: begin
                branch_condition_met = (branch_operand1 < branch_operand2);
                computed_target = branch_pc + branch_immediate;
            end
            
            `BR_GEU: begin
                branch_condition_met = (branch_operand1 >= branch_operand2);
                computed_target = branch_pc + branch_immediate;
            end
            
            `BR_JAL: begin
                branch_condition_met = 1'b1;
                computed_target = branch_pc + branch_immediate;
            end
            
            `BR_JALR: begin
                branch_condition_met = 1'b1;
                computed_target = (branch_operand1 + branch_immediate) & ~32'h00000001;  // Clear LSB
            end
            
            default: begin
                branch_condition_met = 1'b0;
                computed_target = branch_pc + 4;
                branch_computation_exception = 1'b1;
            end
        endcase
    end
    
    // =============================================================================
    // Misprediction Detection
    // =============================================================================
    
    wire actual_taken;
    wire [`XLEN-1:0] actual_target;
    wire prediction_correct;
    
    assign actual_taken = branch_condition_met;
    assign actual_target = branch_condition_met ? computed_target : (branch_pc + 4);
    assign prediction_correct = (branch_predicted_taken == actual_taken) && 
                               (!actual_taken || (branch_predicted_target == actual_target));
    
    // =============================================================================
    // Pipeline Register and Output Logic
    // =============================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            branch_result_pc <= {`XLEN{1'b0}};
            branch_result_instruction <= 32'b0;
            branch_result <= {`XLEN{1'b0}};
            branch_result_phys_rd <= {`PHYS_REG_BITS{1'b0}};
            branch_result_arch_rd <= 5'b0;
            branch_result_rob_id <= {`ROB_ADDR_BITS{1'b0}};
            branch_result_valid <= 1'b0;
            branch_taken <= 1'b0;
            branch_target <= {`XLEN{1'b0}};
            branch_mispredicted <= 1'b0;
            branch_exception <= 1'b0;
            branch_exception_code <= 4'b0;
        end
        else if (flush_branch) begin
            branch_result_valid <= 1'b0;
            branch_mispredicted <= 1'b0;
            branch_exception <= 1'b0;
        end
        else if (!stall_branch) begin
            branch_result_pc <= branch_pc;
            branch_result_instruction <= branch_instruction;
            branch_result_phys_rd <= branch_phys_rd;
            branch_result_arch_rd <= branch_arch_rd;
            branch_result_rob_id <= branch_rob_id;
            branch_result_valid <= branch_valid;
            branch_taken <= actual_taken;
            branch_target <= actual_target;
            branch_mispredicted <= !prediction_correct && branch_valid;
            branch_exception <= branch_computation_exception;
            branch_exception_code <= branch_computation_exception ? `EXCEPT_ILLEGAL_INST : `EXCEPT_NONE;
            
            // Set result for JAL/JALR (link address)
            if ((branch_op == `BR_JAL) || (branch_op == `BR_JALR)) begin
                branch_result <= link_address;
            end else begin
                branch_result <= {`XLEN{1'b0}};  // Regular branches don't write to register
            end
        end
    end
    
    // =============================================================================
    // Bypass/Forwarding Interface
    // =============================================================================
    
    assign branch_bypass_tag = branch_result_phys_rd;
    assign branch_bypass_data = branch_result;
    assign branch_bypass_valid = branch_result_valid && !branch_exception && 
                                (branch_op == `BR_JAL || branch_op == `BR_JALR);

endmodule

// =============================================================================
// Load/Store Unit
// =============================================================================
// Handles memory operations and address calculation

module load_store_unit (
    input wire clk,
    input wire rst_n,
    
    // Input from reservation station
    input wire [`XLEN-1:0] lsu_pc,
    input wire [31:0] lsu_instruction,
    input wire [`XLEN-1:0] lsu_operand1,       // Base address
    input wire [`XLEN-1:0] lsu_operand2,       // Store data
    input wire [31:0] lsu_immediate,           // Offset
    input wire [`PHYS_REG_BITS-1:0] lsu_phys_rd,
    input wire [4:0] lsu_arch_rd,
    input wire [2:0] lsu_mem_op,
    input wire [`ROB_ADDR_BITS-1:0] lsu_rob_id,
    input wire lsu_is_load,
    input wire lsu_is_store,
    input wire lsu_valid,
    
    // Memory interface (to D-cache)
    output reg [`XLEN-1:0] dcache_addr,
    output reg [31:0] dcache_wdata,
    output reg [3:0] dcache_be,                // Byte enable
    output reg dcache_we,                      // Write enable
    output reg dcache_req,
    input wire dcache_ready,
    input wire dcache_valid,
    input wire [31:0] dcache_rdata,
    input wire dcache_error,
    
    // Output to ROB
    output reg [`XLEN-1:0] lsu_result_pc,
    output reg [31:0] lsu_result_instruction,
    output reg [`XLEN-1:0] lsu_result,
    output reg [`PHYS_REG_BITS-1:0] lsu_result_phys_rd,
    output reg [4:0] lsu_result_arch_rd,
    output reg [`ROB_ADDR_BITS-1:0] lsu_result_rob_id,
    output reg lsu_result_valid,
    output reg lsu_exception,
    output reg [3:0] lsu_exception_code,
    
    // Bypass/forwarding output
    output wire [`PHYS_REG_BITS-1:0] lsu_bypass_tag,
    output wire [`XLEN-1:0] lsu_bypass_data,
    output wire lsu_bypass_valid,
    
    // Pipeline control
    input wire stall_lsu,
    input wire flush_lsu
);

    // =============================================================================
    // Address Calculation
    // =============================================================================
    
    wire [`XLEN-1:0] effective_address;
    reg address_misaligned;
    reg [`XLEN-1:0] computed_result;
    reg lsu_computation_exception;
    reg [3:0] computed_exception_code;
    
    assign effective_address = lsu_operand1 + lsu_immediate;
    
    // Address alignment check
    always @(*) begin
        case (lsu_mem_op)
            `MEM_LH, `MEM_LHU, `MEM_SH: begin
                address_misaligned = effective_address[0];
            end
            `MEM_LW, `MEM_SW: begin
                address_misaligned = |effective_address[1:0];
            end
            default: begin
                address_misaligned = 1'b0;  // Byte operations are always aligned
            end
        endcase
    end
    
    // =============================================================================
    // Load Data Processing
    // =============================================================================
    
    always @(*) begin
        computed_result = {`XLEN{1'b0}};
        lsu_computation_exception = 1'b0;
        computed_exception_code = `EXCEPT_NONE;
        
        if (address_misaligned) begin
            lsu_computation_exception = 1'b1;
            computed_exception_code = lsu_is_load ? `EXCEPT_LOAD_ADDR_MISALIGN : `EXCEPT_STORE_ADDR_MISALIGN;
        end
        else if (lsu_is_load && dcache_valid) begin
            case (lsu_mem_op)
                `MEM_LB: begin
                    case (effective_address[1:0])
                        2'b00: computed_result = {{24{dcache_rdata[7]}}, dcache_rdata[7:0]};
                        2'b01: computed_result = {{24{dcache_rdata[15]}}, dcache_rdata[15:8]};
                        2'b10: computed_result = {{24{dcache_rdata[23]}}, dcache_rdata[23:16]};
                        2'b11: computed_result = {{24{dcache_rdata[31]}}, dcache_rdata[31:24]};
                    endcase
                end
                
                `MEM_LBU: begin
                    case (effective_address[1:0])
                        2'b00: computed_result = {24'b0, dcache_rdata[7:0]};
                        2'b01: computed_result = {24'b0, dcache_rdata[15:8]};
                        2'b10: computed_result = {24'b0, dcache_rdata[23:16]};
                        2'b11: computed_result = {24'b0, dcache_rdata[31:24]};
                    endcase
                end
                
                `MEM_LH: begin
                    case (effective_address[1])
                        1'b0: computed_result = {{16{dcache_rdata[15]}}, dcache_rdata[15:0]};
                        1'b1: computed_result = {{16{dcache_rdata[31]}}, dcache_rdata[31:16]};
                    endcase
                end
                
                `MEM_LHU: begin
                    case (effective_address[1])
                        1'b0: computed_result = {16'b0, dcache_rdata[15:0]};
                        1'b1: computed_result = {16'b0, dcache_rdata[31:16]};
                    endcase
                end
                
                `MEM_LW: begin
                    computed_result = dcache_rdata;
                end
                
                default: begin
                    computed_result = {`XLEN{1'b0}};
                    lsu_computation_exception = 1'b1;
                    computed_exception_code = `EXCEPT_ILLEGAL_INST;
                end
            endcase
        end
    end
    
    // =============================================================================
    // Store Data Processing
    // =============================================================================
    
    always @(*) begin
        dcache_addr = effective_address;
        dcache_wdata = 32'b0;
        dcache_be = 4'b0000;
        dcache_we = 1'b0;
        dcache_req = 1'b0;
        
        if (lsu_valid && !lsu_computation_exception) begin
            if (lsu_is_store) begin
                dcache_we = 1'b1;
                dcache_req = 1'b1;
                
                case (lsu_mem_op)
                    `MEM_SB: begin
                        case (effective_address[1:0])
                            2'b00: begin
                                dcache_wdata = {24'b0, lsu_operand2[7:0]};
                                dcache_be = 4'b0001;
                            end
                            2'b01: begin
                                dcache_wdata = {16'b0, lsu_operand2[7:0], 8'b0};
                                dcache_be = 4'b0010;
                            end
                            2'b10: begin
                                dcache_wdata = {8'b0, lsu_operand2[7:0], 16'b0};
                                dcache_be = 4'b0100;
                            end
                            2'b11: begin
                                dcache_wdata = {lsu_operand2[7:0], 24'b0};
                                dcache_be = 4'b1000;
                            end
                        endcase
                    end
                    
                    `MEM_SH: begin
                        case (effective_address[1])
                            1'b0: begin
                                dcache_wdata = {16'b0, lsu_operand2[15:0]};
                                dcache_be = 4'b0011;
                            end
                            1'b1: begin
                                dcache_wdata = {lsu_operand2[15:0], 16'b0};
                                dcache_be = 4'b1100;
                            end
                        endcase
                    end
                    
                    `MEM_SW: begin
                        dcache_wdata = lsu_operand2;
                        dcache_be = 4'b1111;
                    end
                    
                    default: begin
                        dcache_wdata = 32'b0;
                        dcache_be = 4'b0000;
                        dcache_we = 1'b0;
                        dcache_req = 1'b0;
                    end
                endcase
            end
            else if (lsu_is_load) begin
                dcache_we = 1'b0;
                dcache_req = 1'b1;
            end
        end
    end
    
    // =============================================================================
    // Pipeline Register and Output Logic
    // =============================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lsu_result_pc <= {`XLEN{1'b0}};
            lsu_result_instruction <= 32'b0;
            lsu_result <= {`XLEN{1'b0}};
            lsu_result_phys_rd <= {`PHYS_REG_BITS{1'b0}};
            lsu_result_arch_rd <= 5'b0;
            lsu_result_rob_id <= {`ROB_ADDR_BITS{1'b0}};
            lsu_result_valid <= 1'b0;
            lsu_exception <= 1'b0;
            lsu_exception_code <= 4'b0;
        end
        else if (flush_lsu) begin
            lsu_result_valid <= 1'b0;
            lsu_exception <= 1'b0;
        end
        else if (!stall_lsu) begin
            lsu_result_pc <= lsu_pc;
            lsu_result_instruction <= lsu_instruction;
            lsu_result_phys_rd <= lsu_phys_rd;
            lsu_result_arch_rd <= lsu_arch_rd;
            lsu_result_rob_id <= lsu_rob_id;
            lsu_exception <= lsu_computation_exception || dcache_error;
            lsu_exception_code <= dcache_error ? `EXCEPT_LOAD_ACCESS_FAULT : computed_exception_code;
            
            // Handle load completion
            if (lsu_is_load && dcache_valid && !lsu_computation_exception) begin
                lsu_result <= computed_result;
                lsu_result_valid <= 1'b1;
            end
            // Handle store completion
            else if (lsu_is_store && dcache_ready && !lsu_computation_exception) begin
                lsu_result <= {`XLEN{1'b0}};  // Stores don't return data
                lsu_result_valid <= 1'b1;
            end
            else begin
                lsu_result_valid <= 1'b0;
            end
        end
    end
    
    // =============================================================================
    // Bypass/Forwarding Interface
    // =============================================================================
    
    assign lsu_bypass_tag = lsu_result_phys_rd;
    assign lsu_bypass_data = lsu_result;
    assign lsu_bypass_valid = lsu_result_valid && !lsu_exception && lsu_is_load;

endmodule
