// =============================================================================
// Register Rename Unit
// =============================================================================
// File: rename_unit.v
// Description: Register Alias Table (RAT) and rename stage for OoO processor
// Author: Suryaa Senthilkumar Shanthi
// Date: 9 July 2025
// =============================================================================

`include "ooo_processor_defines.vh"

// =============================================================================
// Register Alias Table (RAT)
// =============================================================================
// Maps architectural registers to physical registers

module register_alias_table (
    input wire clk,
    input wire rst_n,
    
    // Lookup interface (for register renaming)
    input wire [4:0] lookup_arch_reg1,
    input wire [4:0] lookup_arch_reg2,
    input wire [4:0] lookup_arch_reg3,
    input wire [4:0] lookup_arch_reg4,
    input wire lookup_enable1,
    input wire lookup_enable2,
    input wire lookup_enable3,
    input wire lookup_enable4,
    
    output wire [`PHYS_REG_BITS-1:0] phys_reg1,
    output wire [`PHYS_REG_BITS-1:0] phys_reg2,
    output wire [`PHYS_REG_BITS-1:0] phys_reg3,
    output wire [`PHYS_REG_BITS-1:0] phys_reg4,
    output wire valid1,
    output wire valid2,
    output wire valid3,
    output wire valid4,
    
    // Update interface (when new mappings are created)
    input wire [4:0] update_arch_reg1,
    input wire [4:0] update_arch_reg2,
    input wire [`PHYS_REG_BITS-1:0] update_phys_reg1,
    input wire [`PHYS_REG_BITS-1:0] update_phys_reg2,
    input wire update_enable1,
    input wire update_enable2,
    
    // Commit interface (architectural state update)
    input wire [4:0] commit_arch_reg1,
    input wire [4:0] commit_arch_reg2,
    input wire [`PHYS_REG_BITS-1:0] commit_phys_reg1,
    input wire [`PHYS_REG_BITS-1:0] commit_phys_reg2,
    input wire commit_enable1,
    input wire commit_enable2,
    
    // Flush interface (for branch misprediction recovery)
    input wire flush_enable,
    input wire [`ARCH_REGS-1:0] flush_arch_valid,
    input wire [`ARCH_REGS*`PHYS_REG_BITS-1:0] flush_phys_regs_flat,
    
    // Debug interface
    output wire [`ARCH_REGS*`PHYS_REG_BITS-1:0] debug_rat_table_flat
);

    // =============================================================================
    // Internal Storage
    // =============================================================================
    
    // Speculative RAT (updated on rename)
    reg [`PHYS_REG_BITS-1:0] speculative_rat [`ARCH_REGS-1:0];
    reg [`ARCH_REGS-1:0] speculative_valid;
    
    // Architectural RAT (updated on commit)
    reg [`PHYS_REG_BITS-1:0] architectural_rat [`ARCH_REGS-1:0];
    reg [`ARCH_REGS-1:0] architectural_valid;
    
    // =============================================================================
    // Initialization
    // =============================================================================
    
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize RAT with identity mapping (arch reg i maps to phys reg i)
            for (i = 0; i < `ARCH_REGS; i = i + 1) begin
                speculative_rat[i] <= i;
                architectural_rat[i] <= i;
            end
            speculative_valid <= {`ARCH_REGS{1'b1}};
            architectural_valid <= {`ARCH_REGS{1'b1}};
        end
        else begin
            // Handle flush (branch misprediction recovery)
            if (flush_enable) begin
                for (i = 0; i < `ARCH_REGS; i = i + 1) begin
                    if (flush_arch_valid[i]) begin
                        speculative_rat[i] <= flush_phys_regs_flat[(i+1)*`PHYS_REG_BITS-1 -: `PHYS_REG_BITS];
                        speculative_valid[i] <= 1'b1;
                    end else begin
                        speculative_rat[i] <= architectural_rat[i];
                        speculative_valid[i] <= architectural_valid[i];
                    end
                end
            end
            else begin
                // Normal operation - handle updates
                if (update_enable1 && !`IS_REG_ZERO(update_arch_reg1)) begin
                    speculative_rat[update_arch_reg1] <= update_phys_reg1;
                    speculative_valid[update_arch_reg1] <= 1'b1;
                end
                
                if (update_enable2 && !`IS_REG_ZERO(update_arch_reg2)) begin
                    speculative_rat[update_arch_reg2] <= update_phys_reg2;
                    speculative_valid[update_arch_reg2] <= 1'b1;
                end
                
                // Handle commits (update architectural state)
                if (commit_enable1 && !`IS_REG_ZERO(commit_arch_reg1)) begin
                    architectural_rat[commit_arch_reg1] <= commit_phys_reg1;
                    architectural_valid[commit_arch_reg1] <= 1'b1;
                end
                
                if (commit_enable2 && !`IS_REG_ZERO(commit_arch_reg2)) begin
                    architectural_rat[commit_arch_reg2] <= commit_phys_reg2;
                    architectural_valid[commit_arch_reg2] <= 1'b1;
                end
            end
        end
    end
    
    // =============================================================================
    // Lookup Logic (Combinational)
    // =============================================================================
    
    // Handle register 0 specially (always maps to physical register 0)
    assign phys_reg1 = lookup_enable1 ? 
                      (`IS_REG_ZERO(lookup_arch_reg1) ? {`PHYS_REG_BITS{1'b0}} : speculative_rat[lookup_arch_reg1]) : 
                      {`PHYS_REG_BITS{1'b0}};
                      
    assign phys_reg2 = lookup_enable2 ? 
                      (`IS_REG_ZERO(lookup_arch_reg2) ? {`PHYS_REG_BITS{1'b0}} : speculative_rat[lookup_arch_reg2]) : 
                      {`PHYS_REG_BITS{1'b0}};
                      
    assign phys_reg3 = lookup_enable3 ? 
                      (`IS_REG_ZERO(lookup_arch_reg3) ? {`PHYS_REG_BITS{1'b0}} : speculative_rat[lookup_arch_reg3]) : 
                      {`PHYS_REG_BITS{1'b0}};
                      
    assign phys_reg4 = lookup_enable4 ? 
                      (`IS_REG_ZERO(lookup_arch_reg4) ? {`PHYS_REG_BITS{1'b0}} : speculative_rat[lookup_arch_reg4]) : 
                      {`PHYS_REG_BITS{1'b0}};
    
    assign valid1 = lookup_enable1 ? 
                   (`IS_REG_ZERO(lookup_arch_reg1) ? 1'b1 : speculative_valid[lookup_arch_reg1]) : 
                   1'b0;
                   
    assign valid2 = lookup_enable2 ? 
                   (`IS_REG_ZERO(lookup_arch_reg2) ? 1'b1 : speculative_valid[lookup_arch_reg2]) : 
                   1'b0;
                   
    assign valid3 = lookup_enable3 ? 
                   (`IS_REG_ZERO(lookup_arch_reg3) ? 1'b1 : speculative_valid[lookup_arch_reg3]) : 
                   1'b0;
                   
    assign valid4 = lookup_enable4 ? 
                   (`IS_REG_ZERO(lookup_arch_reg4) ? 1'b1 : speculative_valid[lookup_arch_reg4]) : 
                   1'b0;
    
    // =============================================================================
    // Debug Interface
    // =============================================================================
    
    genvar j;
    generate
        for (j = 0; j < `ARCH_REGS; j = j + 1) begin : debug_assignment
            assign debug_rat_table_flat[(j+1)*`PHYS_REG_BITS-1 -: `PHYS_REG_BITS] = speculative_rat[j];
        end
    endgenerate

endmodule

// =============================================================================
// Rename Stage
// =============================================================================
// Complete rename pipeline stage that coordinates RAT, free list, and ROB

module rename_stage (
    input wire clk,
    input wire rst_n,
    
    // Input from decode stage
    input wire [`XLEN-1:0] decode_pc1,
    input wire [`XLEN-1:0] decode_pc2,
    input wire [31:0] decode_instruction1,
    input wire [31:0] decode_instruction2,
    input wire [4:0] decode_rs1_1,
    input wire [4:0] decode_rs2_1,
    input wire [4:0] decode_rd_1,
    input wire [4:0] decode_rs1_2,
    input wire [4:0] decode_rs2_2,
    input wire [4:0] decode_rd_2,
    input wire [31:0] decode_immediate1,
    input wire [31:0] decode_immediate2,
    input wire [2:0] decode_inst_type1,
    input wire [2:0] decode_inst_type2,
    input wire [1:0] decode_exec_unit1,
    input wire [1:0] decode_exec_unit2,
    input wire [3:0] decode_alu_op1,
    input wire [3:0] decode_alu_op2,
    input wire [2:0] decode_branch_op1,
    input wire [2:0] decode_branch_op2,
    input wire [2:0] decode_mem_op1,
    input wire [2:0] decode_mem_op2,
    input wire decode_valid1,
    input wire decode_valid2,
    
    // Output to reservation station/ROB
    output reg [`XLEN-1:0] rename_pc1,
    output reg [`XLEN-1:0] rename_pc2,
    output reg [31:0] rename_instruction1,
    output reg [31:0] rename_instruction2,
    output reg [`PHYS_REG_BITS-1:0] rename_phys_rs1_1,
    output reg [`PHYS_REG_BITS-1:0] rename_phys_rs2_1,
    output reg [`PHYS_REG_BITS-1:0] rename_phys_rd_1,
    output reg [`PHYS_REG_BITS-1:0] rename_phys_rs1_2,
    output reg [`PHYS_REG_BITS-1:0] rename_phys_rs2_2,
    output reg [`PHYS_REG_BITS-1:0] rename_phys_rd_2,
    output reg [4:0] rename_arch_rd_1,
    output reg [4:0] rename_arch_rd_2,
    output reg [31:0] rename_immediate1,
    output reg [31:0] rename_immediate2,
    output reg [2:0] rename_inst_type1,
    output reg [2:0] rename_inst_type2,
    output reg [1:0] rename_exec_unit1,
    output reg [1:0] rename_exec_unit2,
    output reg [3:0] rename_alu_op1,
    output reg [3:0] rename_alu_op2,
    output reg [2:0] rename_branch_op1,
    output reg [2:0] rename_branch_op2,
    output reg [2:0] rename_mem_op1,
    output reg [2:0] rename_mem_op2,
    output reg [`ROB_ADDR_BITS-1:0] rename_rob_id1,
    output reg [`ROB_ADDR_BITS-1:0] rename_rob_id2,
    output reg rename_valid1,
    output reg rename_valid2,
    
    // Interface to RAT
    output wire [4:0] rat_lookup_rs1_1,
    output wire [4:0] rat_lookup_rs2_1,
    output wire [4:0] rat_lookup_rs1_2,
    output wire [4:0] rat_lookup_rs2_2,
    output wire rat_lookup_enable1,
    output wire rat_lookup_enable2,
    output wire rat_lookup_enable3,
    output wire rat_lookup_enable4,
    input wire [`PHYS_REG_BITS-1:0] rat_phys_rs1_1,
    input wire [`PHYS_REG_BITS-1:0] rat_phys_rs2_1,
    input wire [`PHYS_REG_BITS-1:0] rat_phys_rs1_2,
    input wire [`PHYS_REG_BITS-1:0] rat_phys_rs2_2,
    input wire rat_valid1,
    input wire rat_valid2,
    input wire rat_valid3,
    input wire rat_valid4,
    
    output reg [4:0] rat_update_arch_reg1,
    output reg [4:0] rat_update_arch_reg2,
    output reg [`PHYS_REG_BITS-1:0] rat_update_phys_reg1,
    output reg [`PHYS_REG_BITS-1:0] rat_update_phys_reg2,
    output reg rat_update_enable1,
    output reg rat_update_enable2,
    
    // Interface to free list
    output wire free_list_allocate_req1,
    output wire free_list_allocate_req2,
    input wire [`PHYS_REG_BITS-1:0] free_list_allocated_reg1,
    input wire [`PHYS_REG_BITS-1:0] free_list_allocated_reg2,
    input wire free_list_allocation_valid1,
    input wire free_list_allocation_valid2,
    
    // Interface to ROB (for ROB ID allocation)
    output wire rob_allocate_req1,
    output wire rob_allocate_req2,
    input wire [`ROB_ADDR_BITS-1:0] rob_allocated_id1,
    input wire [`ROB_ADDR_BITS-1:0] rob_allocated_id2,
    input wire rob_allocation_valid1,
    input wire rob_allocation_valid2,
    
    // Pipeline control
    input wire stall_rename,
    input wire flush_rename,
    output wire rename_stall_req
);

    // =============================================================================
    // RAT Lookup Logic
    // =============================================================================
    
    assign rat_lookup_rs1_1 = decode_rs1_1;
    assign rat_lookup_rs2_1 = decode_rs2_1;
    assign rat_lookup_rs1_2 = decode_rs1_2;
    assign rat_lookup_rs2_2 = decode_rs2_2;
    
    assign rat_lookup_enable1 = decode_valid1;
    assign rat_lookup_enable2 = decode_valid1;
    assign rat_lookup_enable3 = decode_valid2;
    assign rat_lookup_enable4 = decode_valid2;
    
    // =============================================================================
    // Resource Allocation Logic
    // =============================================================================
    
    wire need_phys_reg1, need_phys_reg2;
    wire need_rob_entry1, need_rob_entry2;
    
    // Need physical register if destination is not x0
    assign need_phys_reg1 = decode_valid1 && !`IS_REG_ZERO(decode_rd_1);
    assign need_phys_reg2 = decode_valid2 && !`IS_REG_ZERO(decode_rd_2);
    
    // Need ROB entry for all valid instructions
    assign need_rob_entry1 = decode_valid1;
    assign need_rob_entry2 = decode_valid2;
    
    assign free_list_allocate_req1 = need_phys_reg1;
    assign free_list_allocate_req2 = need_phys_reg2;
    
    assign rob_allocate_req1 = need_rob_entry1;
    assign rob_allocate_req2 = need_rob_entry2;
    
    // =============================================================================
    // Stall Logic
    // =============================================================================
    
    wire resource_stall;
    
    // Stall if we can't get required resources
    assign resource_stall = (need_phys_reg1 && !free_list_allocation_valid1) ||
                           (need_phys_reg2 && !free_list_allocation_valid2) ||
                           (need_rob_entry1 && !rob_allocation_valid1) ||
                           (need_rob_entry2 && !rob_allocation_valid2);
    
    assign rename_stall_req = resource_stall;
    
    // =============================================================================
    // Rename Pipeline Stage
    // =============================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all outputs
            rename_pc1 <= {`XLEN{1'b0}};
            rename_pc2 <= {`XLEN{1'b0}};
            rename_instruction1 <= 32'b0;
            rename_instruction2 <= 32'b0;
            rename_phys_rs1_1 <= {`PHYS_REG_BITS{1'b0}};
            rename_phys_rs2_1 <= {`PHYS_REG_BITS{1'b0}};
            rename_phys_rd_1 <= {`PHYS_REG_BITS{1'b0}};
            rename_phys_rs1_2 <= {`PHYS_REG_BITS{1'b0}};
            rename_phys_rs2_2 <= {`PHYS_REG_BITS{1'b0}};
            rename_phys_rd_2 <= {`PHYS_REG_BITS{1'b0}};
            rename_arch_rd_1 <= 5'b0;
            rename_arch_rd_2 <= 5'b0;
            rename_immediate1 <= 32'b0;
            rename_immediate2 <= 32'b0;
            rename_inst_type1 <= 3'b0;
            rename_inst_type2 <= 3'b0;
            rename_exec_unit1 <= 2'b0;
            rename_exec_unit2 <= 2'b0;
            rename_alu_op1 <= 4'b0;
            rename_alu_op2 <= 4'b0;
            rename_branch_op1 <= 3'b0;
            rename_branch_op2 <= 3'b0;
            rename_mem_op1 <= 3'b0;
            rename_mem_op2 <= 3'b0;
            rename_rob_id1 <= {`ROB_ADDR_BITS{1'b0}};
            rename_rob_id2 <= {`ROB_ADDR_BITS{1'b0}};
            rename_valid1 <= 1'b0;
            rename_valid2 <= 1'b0;
            
            rat_update_arch_reg1 <= 5'b0;
            rat_update_arch_reg2 <= 5'b0;
            rat_update_phys_reg1 <= {`PHYS_REG_BITS{1'b0}};
            rat_update_phys_reg2 <= {`PHYS_REG_BITS{1'b0}};
            rat_update_enable1 <= 1'b0;
            rat_update_enable2 <= 1'b0;
        end
        else if (flush_rename) begin
            // Flush pipeline stage
            rename_valid1 <= 1'b0;
            rename_valid2 <= 1'b0;
            rat_update_enable1 <= 1'b0;
            rat_update_enable2 <= 1'b0;
        end
        else if (!stall_rename && !resource_stall) begin
            // Normal operation - process instructions
            
            // Instruction 1
            if (decode_valid1) begin
                rename_pc1 <= decode_pc1;
                rename_instruction1 <= decode_instruction1;
                rename_phys_rs1_1 <= rat_phys_rs1_1;
                rename_phys_rs2_1 <= rat_phys_rs2_1;
                rename_arch_rd_1 <= decode_rd_1;
                rename_immediate1 <= decode_immediate1;
                rename_inst_type1 <= decode_inst_type1;
                rename_exec_unit1 <= decode_exec_unit1;
                rename_alu_op1 <= decode_alu_op1;
                rename_branch_op1 <= decode_branch_op1;
                rename_mem_op1 <= decode_mem_op1;
                rename_rob_id1 <= rob_allocated_id1;
                rename_valid1 <= 1'b1;
                
                // Assign physical destination register
                if (need_phys_reg1) begin
                    rename_phys_rd_1 <= free_list_allocated_reg1;
                    rat_update_arch_reg1 <= decode_rd_1;
                    rat_update_phys_reg1 <= free_list_allocated_reg1;
                    rat_update_enable1 <= 1'b1;
                end else begin
                    rename_phys_rd_1 <= {`PHYS_REG_BITS{1'b0}};
                    rat_update_enable1 <= 1'b0;
                end
            end else begin
                rename_valid1 <= 1'b0;
                rat_update_enable1 <= 1'b0;
            end
            
            // Instruction 2
            if (decode_valid2) begin
                rename_pc2 <= decode_pc2;
                rename_instruction2 <= decode_instruction2;
                rename_phys_rs1_2 <= rat_phys_rs1_2;
                rename_phys_rs2_2 <= rat_phys_rs2_2;
                rename_arch_rd_2 <= decode_rd_2;
                rename_immediate2 <= decode_immediate2;
                rename_inst_type2 <= decode_inst_type2;
                rename_exec_unit2 <= decode_exec_unit2;
                rename_alu_op2 <= decode_alu_op2;
                rename_branch_op2 <= decode_branch_op2;
                rename_mem_op2 <= decode_mem_op2;
                rename_rob_id2 <= rob_allocated_id2;
                rename_valid2 <= 1'b1;
                
                // Assign physical destination register
                if (need_phys_reg2) begin
                    rename_phys_rd_2 <= free_list_allocated_reg2;
                    rat_update_arch_reg2 <= decode_rd_2;
                    rat_update_phys_reg2 <= free_list_allocated_reg2;
                    rat_update_enable2 <= 1'b1;
                end else begin
                    rename_phys_rd_2 <= {`PHYS_REG_BITS{1'b0}};
                    rat_update_enable2 <= 1'b0;
                end
            end else begin
                rename_valid2 <= 1'b0;
                rat_update_enable2 <= 1'b0;
            end
        end
        // If stalled, maintain current outputs
    end

endmodule
