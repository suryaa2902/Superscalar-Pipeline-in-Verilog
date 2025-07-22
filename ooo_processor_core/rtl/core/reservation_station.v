// =============================================================================
// Reservation Station
// =============================================================================
// File: reservation_station.v
// Description: Reservation station and instruction scheduler for OoO processor
// Author: Suryaa Senthilkumar Shanthi
// Date: 11 July 2025
// =============================================================================

`include "ooo_processor_defines.vh"

// =============================================================================
// Reservation Station Controller
// =============================================================================
// Manages instruction allocation, wakeup, and issue logic

module rs_controller (
    input wire clk,
    input wire rst_n,
    
    // Allocation interface (from rename stage)
    input wire [`XLEN-1:0] alloc_pc1,
    input wire [`XLEN-1:0] alloc_pc2,
    input wire [31:0] alloc_instruction1,
    input wire [31:0] alloc_instruction2,
    input wire [`PHYS_REG_BITS-1:0] alloc_phys_rs1_1,
    input wire [`PHYS_REG_BITS-1:0] alloc_phys_rs2_1,
    input wire [`PHYS_REG_BITS-1:0] alloc_phys_rd_1,
    input wire [`PHYS_REG_BITS-1:0] alloc_phys_rs1_2,
    input wire [`PHYS_REG_BITS-1:0] alloc_phys_rs2_2,
    input wire [`PHYS_REG_BITS-1:0] alloc_phys_rd_2,
    input wire [4:0] alloc_arch_rd_1,
    input wire [4:0] alloc_arch_rd_2,
    input wire [31:0] alloc_immediate1,
    input wire [31:0] alloc_immediate2,
    input wire [2:0] alloc_inst_type1,
    input wire [2:0] alloc_inst_type2,
    input wire [1:0] alloc_exec_unit1,
    input wire [1:0] alloc_exec_unit2,
    input wire [3:0] alloc_alu_op1,
    input wire [3:0] alloc_alu_op2,
    input wire [2:0] alloc_branch_op1,
    input wire [2:0] alloc_branch_op2,
    input wire [2:0] alloc_mem_op1,
    input wire [2:0] alloc_mem_op2,
    input wire [`ROB_ADDR_BITS-1:0] alloc_rob_id1,
    input wire [`ROB_ADDR_BITS-1:0] alloc_rob_id2,
    input wire alloc_valid1,
    input wire alloc_valid2,
    
    output wire [`RS_ADDR_BITS-1:0] allocated_rs_id1,
    output wire [`RS_ADDR_BITS-1:0] allocated_rs_id2,
    output wire allocation_success1,
    output wire allocation_success2,
    
    // Register file read interface
    output wire [`PHYS_REG_BITS-1:0] regfile_read_addr1,
    output wire [`PHYS_REG_BITS-1:0] regfile_read_addr2,
    output wire [`PHYS_REG_BITS-1:0] regfile_read_addr3,
    output wire [`PHYS_REG_BITS-1:0] regfile_read_addr4,
    output wire regfile_read_enable1,
    output wire regfile_read_enable2,
    output wire regfile_read_enable3,
    output wire regfile_read_enable4,
    input wire [`XLEN-1:0] regfile_read_data1,
    input wire [`XLEN-1:0] regfile_read_data2,
    input wire [`XLEN-1:0] regfile_read_data3,
    input wire [`XLEN-1:0] regfile_read_data4,
    
    // Register ready interface
    output wire [`PHYS_REG_BITS-1:0] regfile_ready_addr1,
    output wire [`PHYS_REG_BITS-1:0] regfile_ready_addr2,
    input wire regfile_ready_out1,
    input wire regfile_ready_out2,
    
    // Wakeup interface (from execution units)
    input wire [`PHYS_REG_BITS-1:0] wakeup_tag1,
    input wire [`PHYS_REG_BITS-1:0] wakeup_tag2,
    input wire wakeup_valid1,
    input wire wakeup_valid2,
    
    // Issue interface (to execution units)
    output wire [`XLEN-1:0] issue_pc1,
    output wire [`XLEN-1:0] issue_pc2,
    output wire [31:0] issue_instruction1,
    output wire [31:0] issue_instruction2,
    output wire [`XLEN-1:0] issue_operand1_1,
    output wire [`XLEN-1:0] issue_operand2_1,
    output wire [`XLEN-1:0] issue_operand1_2,
    output wire [`XLEN-1:0] issue_operand2_2,
    output wire [`PHYS_REG_BITS-1:0] issue_phys_rd_1,
    output wire [`PHYS_REG_BITS-1:0] issue_phys_rd_2,
    output wire [4:0] issue_arch_rd_1,
    output wire [4:0] issue_arch_rd_2,
    output wire [31:0] issue_immediate1,
    output wire [31:0] issue_immediate2,
    output wire [2:0] issue_inst_type1,
    output wire [2:0] issue_inst_type2,
    output wire [1:0] issue_exec_unit1,
    output wire [1:0] issue_exec_unit2,
    output wire [3:0] issue_alu_op1,
    output wire [3:0] issue_alu_op2,
    output wire [2:0] issue_branch_op1,
    output wire [2:0] issue_branch_op2,
    output wire [2:0] issue_mem_op1,
    output wire [2:0] issue_mem_op2,
    output wire [`ROB_ADDR_BITS-1:0] issue_rob_id1,
    output wire [`ROB_ADDR_BITS-1:0] issue_rob_id2,
    output wire [`RS_ADDR_BITS-1:0] issue_rs_id1,
    output wire [`RS_ADDR_BITS-1:0] issue_rs_id2,
    output wire issue_valid1,
    output wire issue_valid2,
    
    // Pipeline control
    input wire stall_issue,
    input wire flush_rs,
    output wire rs_stall_req,
    
    // Status outputs
    output wire [`RS_ADDR_BITS:0] rs_entries_used,
    output wire rs_full,
    output wire rs_empty
);

    // =============================================================================
    // Reservation Station Entry Storage
    // =============================================================================
    
    // Entry fields (flattened arrays for Verilog compatibility)
    reg [`XLEN-1:0]         rs_pc           [`RS_SIZE-1:0];
    reg [31:0]              rs_instruction  [`RS_SIZE-1:0];
    reg [`XLEN-1:0]         rs_operand1     [`RS_SIZE-1:0];
    reg [`XLEN-1:0]         rs_operand2     [`RS_SIZE-1:0];
    reg                     rs_op1_ready    [`RS_SIZE-1:0];
    reg                     rs_op2_ready    [`RS_SIZE-1:0];
    reg [`PHYS_REG_BITS-1:0] rs_phys_rs1    [`RS_SIZE-1:0];
    reg [`PHYS_REG_BITS-1:0] rs_phys_rs2    [`RS_SIZE-1:0];
    reg [`PHYS_REG_BITS-1:0] rs_phys_rd     [`RS_SIZE-1:0];
    reg [4:0]               rs_arch_rd      [`RS_SIZE-1:0];
    reg [31:0]              rs_immediate    [`RS_SIZE-1:0];
    reg [2:0]               rs_inst_type    [`RS_SIZE-1:0];
    reg [1:0]               rs_exec_unit    [`RS_SIZE-1:0];
    reg [3:0]               rs_alu_op       [`RS_SIZE-1:0];
    reg [2:0]               rs_branch_op    [`RS_SIZE-1:0];
    reg [2:0]               rs_mem_op       [`RS_SIZE-1:0];
    reg [`ROB_ADDR_BITS-1:0] rs_rob_id      [`RS_SIZE-1:0];
    reg [3:0]               rs_age          [`RS_SIZE-1:0];
    reg                     rs_valid        [`RS_SIZE-1:0];
    reg                     rs_issued       [`RS_SIZE-1:0];
    
    // =============================================================================
    // Allocation Logic
    // =============================================================================
    
    wire [`RS_SIZE-1:0] free_entries;
    wire [`RS_SIZE-1:0] can_allocate;
    reg [`RS_ADDR_BITS-1:0] alloc_entry1, alloc_entry2;
    reg entry1_found, entry2_found;
    
    // Find free entries
    genvar i;
    generate
        for (i = 0; i < `RS_SIZE; i = i + 1) begin : find_free
            assign free_entries[i] = !rs_valid[i];
        end
    endgenerate
    
    // Priority encoder for allocation
    integer j, k;
    always @(*) begin
        entry1_found = 1'b0;
        entry2_found = 1'b0;
        alloc_entry1 = {`RS_ADDR_BITS{1'b0}};
        alloc_entry2 = {`RS_ADDR_BITS{1'b0}};
        
        // Find first free entry
        for (j = 0; j < `RS_SIZE; j = j + 1) begin
            if (free_entries[j] && !entry1_found) begin
                alloc_entry1 = j;
                entry1_found = 1'b1;
            end
        end
        
        // Find second free entry
        for (k = 0; k < `RS_SIZE; k = k + 1) begin
            if (free_entries[k] && !entry2_found && (k != alloc_entry1)) begin
                alloc_entry2 = k;
                entry2_found = 1'b1;
            end
        end
    end
    
    assign allocated_rs_id1 = alloc_entry1;
    assign allocated_rs_id2 = alloc_entry2;
    assign allocation_success1 = alloc_valid1 && entry1_found;
    assign allocation_success2 = alloc_valid2 && entry2_found && entry1_found;
    
    // =============================================================================
    // Wakeup Logic
    // =============================================================================
    
    wire [`RS_SIZE-1:0] wakeup_match1_op1, wakeup_match1_op2;
    wire [`RS_SIZE-1:0] wakeup_match2_op1, wakeup_match2_op2;
    
    generate
        for (i = 0; i < `RS_SIZE; i = i + 1) begin : wakeup_logic
            assign wakeup_match1_op1[i] = wakeup_valid1 && rs_valid[i] && 
                                         !rs_op1_ready[i] && (rs_phys_rs1[i] == wakeup_tag1);
            assign wakeup_match1_op2[i] = wakeup_valid1 && rs_valid[i] && 
                                         !rs_op2_ready[i] && (rs_phys_rs2[i] == wakeup_tag1);
            assign wakeup_match2_op1[i] = wakeup_valid2 && rs_valid[i] && 
                                         !rs_op1_ready[i] && (rs_phys_rs1[i] == wakeup_tag2);
            assign wakeup_match2_op2[i] = wakeup_valid2 && rs_valid[i] && 
                                         !rs_op2_ready[i] && (rs_phys_rs2[i] == wakeup_tag2);
        end
    endgenerate
    
    // =============================================================================
    // Issue Logic (Age-based Priority)
    // =============================================================================
    
    wire [`RS_SIZE-1:0] ready_to_issue;
    reg [`RS_ADDR_BITS-1:0] issue_entry1, issue_entry2;
    reg issue1_found, issue2_found;
    reg [3:0] oldest_age1, oldest_age2;
    
    generate
        for (i = 0; i < `RS_SIZE; i = i + 1) begin : issue_ready
            assign ready_to_issue[i] = rs_valid[i] && !rs_issued[i] && 
                                      rs_op1_ready[i] && rs_op2_ready[i];
        end
    endgenerate
    
    // Find oldest ready instruction for issue port 1
    integer m;
    always @(*) begin
        issue1_found = 1'b0;
        issue_entry1 = {`RS_ADDR_BITS{1'b0}};
        oldest_age1 = 4'b0;
        
        for (m = 0; m < `RS_SIZE; m = m + 1) begin
            if (ready_to_issue[m] && (!issue1_found || (rs_age[m] > oldest_age1))) begin
                issue_entry1 = m;
                oldest_age1 = rs_age[m];
                issue1_found = 1'b1;
            end
        end
    end
    
    // Find second oldest ready instruction for issue port 2
    integer n;
    always @(*) begin
        issue2_found = 1'b0;
        issue_entry2 = {`RS_ADDR_BITS{1'b0}};
        oldest_age2 = 4'b0;
        
        for (n = 0; n < `RS_SIZE; n = n + 1) begin
            if (ready_to_issue[n] && (n != issue_entry1) && 
                (!issue2_found || (rs_age[n] > oldest_age2))) begin
                issue_entry2 = n;
                oldest_age2 = rs_age[n];
                issue2_found = 1'b1;
            end
        end
    end
    
    // =============================================================================
    // Register File Interface
    // =============================================================================
    
    // Read addresses for allocation
    assign regfile_read_addr1 = alloc_phys_rs1_1;
    assign regfile_read_addr2 = alloc_phys_rs2_1;
    assign regfile_read_addr3 = alloc_phys_rs1_2;
    assign regfile_read_addr4 = alloc_phys_rs2_2;
    assign regfile_read_enable1 = allocation_success1;
    assign regfile_read_enable2 = allocation_success1;
    assign regfile_read_enable3 = allocation_success2;
    assign regfile_read_enable4 = allocation_success2;
    
    // Ready check addresses
    assign regfile_ready_addr1 = alloc_phys_rs1_1;
    assign regfile_ready_addr2 = alloc_phys_rs2_1;
    
    // =============================================================================
    // Issue Outputs
    // =============================================================================
    
    assign issue_pc1 = rs_pc[issue_entry1];
    assign issue_pc2 = rs_pc[issue_entry2];
    assign issue_instruction1 = rs_instruction[issue_entry1];
    assign issue_instruction2 = rs_instruction[issue_entry2];
    assign issue_operand1_1 = rs_operand1[issue_entry1];
    assign issue_operand2_1 = rs_operand2[issue_entry1];
    assign issue_operand1_2 = rs_operand1[issue_entry2];
    assign issue_operand2_2 = rs_operand2[issue_entry2];
    assign issue_phys_rd_1 = rs_phys_rd[issue_entry1];
    assign issue_phys_rd_2 = rs_phys_rd[issue_entry2];
    assign issue_arch_rd_1 = rs_arch_rd[issue_entry1];
    assign issue_arch_rd_2 = rs_arch_rd[issue_entry2];
    assign issue_immediate1 = rs_immediate[issue_entry1];
    assign issue_immediate2 = rs_immediate[issue_entry2];
    assign issue_inst_type1 = rs_inst_type[issue_entry1];
    assign issue_inst_type2 = rs_inst_type[issue_entry2];
    assign issue_exec_unit1 = rs_exec_unit[issue_entry1];
    assign issue_exec_unit2 = rs_exec_unit[issue_entry2];
    assign issue_alu_op1 = rs_alu_op[issue_entry1];
    assign issue_alu_op2 = rs_alu_op[issue_entry2];
    assign issue_branch_op1 = rs_branch_op[issue_entry1];
    assign issue_branch_op2 = rs_branch_op[issue_entry2];
    assign issue_mem_op1 = rs_mem_op[issue_entry1];
    assign issue_mem_op2 = rs_mem_op[issue_entry2];
    assign issue_rob_id1 = rs_rob_id[issue_entry1];
    assign issue_rob_id2 = rs_rob_id[issue_entry2];
    assign issue_rs_id1 = issue_entry1;
    assign issue_rs_id2 = issue_entry2;
    assign issue_valid1 = issue1_found && !stall_issue;
    assign issue_valid2 = issue2_found && !stall_issue;
    
    // =============================================================================
    // Status Outputs
    // =============================================================================
    
    reg [`RS_ADDR_BITS:0] valid_count;
    integer p;
    
    always @(*) begin
        valid_count = 0;
        for (p = 0; p < `RS_SIZE; p = p + 1) begin
            if (rs_valid[p]) begin
                valid_count = valid_count + 1;
            end
        end
    end
    
    assign rs_entries_used = valid_count;
    assign rs_full = (valid_count >= `RS_SIZE);
    assign rs_empty = (valid_count == 0);
    assign rs_stall_req = rs_full;
    
    // =============================================================================
    // Sequential Logic
    // =============================================================================
    
    integer idx;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize all entries
            for (idx = 0; idx < `RS_SIZE; idx = idx + 1) begin
                rs_pc[idx] <= {`XLEN{1'b0}};
                rs_instruction[idx] <= 32'b0;
                rs_operand1[idx] <= {`XLEN{1'b0}};
                rs_operand2[idx] <= {`XLEN{1'b0}};
                rs_op1_ready[idx] <= 1'b0;
                rs_op2_ready[idx] <= 1'b0;
                rs_phys_rs1[idx] <= {`PHYS_REG_BITS{1'b0}};
                rs_phys_rs2[idx] <= {`PHYS_REG_BITS{1'b0}};
                rs_phys_rd[idx] <= {`PHYS_REG_BITS{1'b0}};
                rs_arch_rd[idx] <= 5'b0;
                rs_immediate[idx] <= 32'b0;
                rs_inst_type[idx] <= 3'b0;
                rs_exec_unit[idx] <= 2'b0;
                rs_alu_op[idx] <= 4'b0;
                rs_branch_op[idx] <= 3'b0;
                rs_mem_op[idx] <= 3'b0;
                rs_rob_id[idx] <= {`ROB_ADDR_BITS{1'b0}};
                rs_age[idx] <= 4'b0;
                rs_valid[idx] <= 1'b0;
                rs_issued[idx] <= 1'b0;
            end
        end
        else if (flush_rs) begin
            // Flush all entries
            for (idx = 0; idx < `RS_SIZE; idx = idx + 1) begin
                rs_valid[idx] <= 1'b0;
                rs_issued[idx] <= 1'b0;
                rs_age[idx] <= 4'b0;
            end
        end
        else begin
            // Age all valid entries
            for (idx = 0; idx < `RS_SIZE; idx = idx + 1) begin
                if (rs_valid[idx] && !rs_issued[idx] && (rs_age[idx] < 4'hF)) begin
                    rs_age[idx] <= rs_age[idx] + 1;
                end
            end
            
            // Handle allocations
            if (allocation_success1) begin
                rs_pc[alloc_entry1] <= alloc_pc1;
                rs_instruction[alloc_entry1] <= alloc_instruction1;
                rs_operand1[alloc_entry1] <= regfile_read_data1;
                rs_operand2[alloc_entry1] <= regfile_read_data2;
                rs_op1_ready[alloc_entry1] <= regfile_ready_out1 || `IS_REG_ZERO(alloc_phys_rs1_1);
                rs_op2_ready[alloc_entry1] <= regfile_ready_out2 || `IS_REG_ZERO(alloc_phys_rs2_1);
                rs_phys_rs1[alloc_entry1] <= alloc_phys_rs1_1;
                rs_phys_rs2[alloc_entry1] <= alloc_phys_rs2_1;
                rs_phys_rd[alloc_entry1] <= alloc_phys_rd_1;
                rs_arch_rd[alloc_entry1] <= alloc_arch_rd_1;
                rs_immediate[alloc_entry1] <= alloc_immediate1;
                rs_inst_type[alloc_entry1] <= alloc_inst_type1;
                rs_exec_unit[alloc_entry1] <= alloc_exec_unit1;
                rs_alu_op[alloc_entry1] <= alloc_alu_op1;
                rs_branch_op[alloc_entry1] <= alloc_branch_op1;
                rs_mem_op[alloc_entry1] <= alloc_mem_op1;
                rs_rob_id[alloc_entry1] <= alloc_rob_id1;
                rs_age[alloc_entry1] <= 4'b0;
                rs_valid[alloc_entry1] <= 1'b1;
                rs_issued[alloc_entry1] <= 1'b0;
            end
            
            if (allocation_success2) begin
                rs_pc[alloc_entry2] <= alloc_pc2;
                rs_instruction[alloc_entry2] <= alloc_instruction2;
                rs_operand1[alloc_entry2] <= regfile_read_data3;
                rs_operand2[alloc_entry2] <= regfile_read_data4;
                rs_op1_ready[alloc_entry2] <= regfile_ready_out1 || `IS_REG_ZERO(alloc_phys_rs1_2);
                rs_op2_ready[alloc_entry2] <= regfile_ready_out2 || `IS_REG_ZERO(alloc_phys_rs2_2);
                rs_phys_rs1[alloc_entry2] <= alloc_phys_rs1_2;
                rs_phys_rs2[alloc_entry2] <= alloc_phys_rs2_2;
                rs_phys_rd[alloc_entry2] <= alloc_phys_rd_2;
                rs_arch_rd[alloc_entry2] <= alloc_arch_rd_2;
                rs_immediate[alloc_entry2] <= alloc_immediate2;
                rs_inst_type[alloc_entry2] <= alloc_inst_type2;
                rs_exec_unit[alloc_entry2] <= alloc_exec_unit2;
                rs_alu_op[alloc_entry2] <= alloc_alu_op2;
                rs_branch_op[alloc_entry2] <= alloc_branch_op2;
                rs_mem_op[alloc_entry2] <= alloc_mem_op2;
                rs_rob_id[alloc_entry2] <= alloc_rob_id2;
                rs_age[alloc_entry2] <= 4'b0;
                rs_valid[alloc_entry2] <= 1'b1;
                rs_issued[alloc_entry2] <= 1'b0;
            end
            
            // Handle wakeups
            for (idx = 0; idx < `RS_SIZE; idx = idx + 1) begin
                if (wakeup_match1_op1[idx]) begin
                    rs_op1_ready[idx] <= 1'b1;
                end
                if (wakeup_match1_op2[idx]) begin
                    rs_op2_ready[idx] <= 1'b1;
                end
                if (wakeup_match2_op1[idx]) begin
                    rs_op1_ready[idx] <= 1'b1;
                end
                if (wakeup_match2_op2[idx]) begin
                    rs_op2_ready[idx] <= 1'b1;
                end
            end
            
            // Handle issues
            if (issue_valid1) begin
                rs_issued[issue_entry1] <= 1'b1;
            end
            
            if (issue_valid2) begin
                rs_issued[issue_entry2] <= 1'b1;
            end
            
            // Remove issued entries (simplified - in reality, wait for completion)
            if (issue_valid1) begin
                rs_valid[issue_entry1] <= 1'b0;
            end
            
            if (issue_valid2) begin
                rs_valid[issue_entry2] <= 1'b0;
            end
        end
    end

endmodule

// =============================================================================
// Instruction Scheduler
// =============================================================================
// Higher-level scheduler that coordinates multiple reservation stations

module instruction_scheduler (
    input wire clk,
    input wire rst_n,
    
    // Input from rename stage
    input wire [`XLEN-1:0] rename_pc1,
    input wire [`XLEN-1:0] rename_pc2,
    input wire [31:0] rename_instruction1,
    input wire [31:0] rename_instruction2,
    input wire [`PHYS_REG_BITS-1:0] rename_phys_rs1_1,
    input wire [`PHYS_REG_BITS-1:0] rename_phys_rs2_1,
    input wire [`PHYS_REG_BITS-1:0] rename_phys_rd_1,
    input wire [`PHYS_REG_BITS-1:0] rename_phys_rs1_2,
    input wire [`PHYS_REG_BITS-1:0] rename_phys_rs2_2,
    input wire [`PHYS_REG_BITS-1:0] rename_phys_rd_2,
    input wire [4:0] rename_arch_rd_1,
    input wire [4:0] rename_arch_rd_2,
    input wire [31:0] rename_immediate1,
    input wire [31:0] rename_immediate2,
    input wire [2:0] rename_inst_type1,
    input wire [2:0] rename_inst_type2,
    input wire [1:0] rename_exec_unit1,
    input wire [1:0] rename_exec_unit2,
    input wire [3:0] rename_alu_op1,
    input wire [3:0] rename_alu_op2,
    input wire [2:0] rename_branch_op1,
    input wire [2:0] rename_branch_op2,
    input wire [2:0] rename_mem_op1,
    input wire [2:0] rename_mem_op2,
    input wire [`ROB_ADDR_BITS-1:0] rename_rob_id1,
    input wire [`ROB_ADDR_BITS-1:0] rename_rob_id2,
    input wire rename_valid1,
    input wire rename_valid2,
    
    // Output to execution units
    output wire [`XLEN-1:0] exec_pc1,
    output wire [`XLEN-1:0] exec_pc2,
    output wire [31:0] exec_instruction1,
    output wire [31:0] exec_instruction2,
    output wire [`XLEN-1:0] exec_operand1_1,
    output wire [`XLEN-1:0] exec_operand2_1,
    output wire [`XLEN-1:0] exec_operand1_2,
    output wire [`XLEN-1:0] exec_operand2_2,
    output wire [`PHYS_REG_BITS-1:0] exec_phys_rd_1,
    output wire [`PHYS_REG_BITS-1:0] exec_phys_rd_2,
    output wire [4:0] exec_arch_rd_1,
    output wire [4:0] exec_arch_rd_2,
    output wire [31:0] exec_immediate1,
    output wire [31:0] exec_immediate2,
    output wire [2:0] exec_inst_type1,
    output wire [2:0] exec_inst_type2,
    output wire [1:0] exec_exec_unit1,
    output wire [1:0] exec_exec_unit2,
    output wire [3:0] exec_alu_op1,
    output wire [3:0] exec_alu_op2,
    output wire [2:0] exec_branch_op1,
    output wire [2:0] exec_branch_op2,
    output wire [2:0] exec_mem_op1,
    output wire [2:0] exec_mem_op2,
    output wire [`ROB_ADDR_BITS-1:0] exec_rob_id1,
    output wire [`ROB_ADDR_BITS-1:0] exec_rob_id2,
    output wire exec_valid1,
    output wire exec_valid2,
    
    // Register file interface
    output wire [`PHYS_REG_BITS-1:0] regfile_read_addr1,
    output wire [`PHYS_REG_BITS-1:0] regfile_read_addr2,
    output wire [`PHYS_REG_BITS-1:0] regfile_read_addr3,
    output wire [`PHYS_REG_BITS-1:0] regfile_read_addr4,
    output wire regfile_read_enable1,
    output wire regfile_read_enable2,
    output wire regfile_read_enable3,
    output wire regfile_read_enable4,
    input wire [`XLEN-1:0] regfile_read_data1,
    input wire [`XLEN-1:0] regfile_read_data2,
    input wire [`XLEN-1:0] regfile_read_data3,
    input wire [`XLEN-1:0] regfile_read_data4,
    
    // Register ready interface
    output wire [`PHYS_REG_BITS-1:0] regfile_ready_addr1,
    output wire [`PHYS_REG_BITS-1:0] regfile_ready_addr2,
    input wire regfile_ready_out1,
    input wire regfile_ready_out2,
    
    // Wakeup interface (from execution units)
    input wire [`PHYS_REG_BITS-1:0] wakeup_tag1,
    input wire [`PHYS_REG_BITS-1:0] wakeup_tag2,
    input wire wakeup_valid1,
    input wire wakeup_valid2,
    
    // Pipeline control
    input wire stall_scheduler,
    input wire flush_scheduler,
    output wire scheduler_stall_req,
    
    // Flow control
    input wire exec_ready,
    output wire rename_ready
);

    // =============================================================================
    // Reservation Station Instance
    // =============================================================================
    
    wire [`RS_ADDR_BITS-1:0] rs_allocated_id1, rs_allocated_id2;
    wire rs_allocation_success1, rs_allocation_success2;
    wire [`RS_ADDR_BITS-1:0] rs_issue_rs_id1, rs_issue_rs_id2;
    wire [`RS_ADDR_BITS:0] rs_entries_used;
    wire rs_full, rs_empty;
    wire rs_stall_req;
    
    rs_controller rs_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        
        // Allocation interface
        .alloc_pc1(rename_pc1),
        .alloc_pc2(rename_pc2),
        .alloc_instruction1(rename_instruction1),
        .alloc_instruction2(rename_instruction2),
        .alloc_phys_rs1_1(rename_phys_rs1_1),
        .alloc_phys_rs2_1(rename_phys_rs2_1),
        .alloc_phys_rd_1(rename_phys_rd_1),
        .alloc_phys_rs1_2(rename_phys_rs1_2),
        .alloc_phys_rs2_2(rename_phys_rs2_2),
        .alloc_phys_rd_2(rename_phys_rd_2),
        .alloc_arch_rd_1(rename_arch_rd_1),
        .alloc_arch_rd_2(rename_arch_rd_2),
        .alloc_immediate1(rename_immediate1),
        .alloc_immediate2(rename_immediate2),
        .alloc_inst_type1(rename_inst_type1),
        .alloc_inst_type2(rename_inst_type2),
        .alloc_exec_unit1(rename_exec_unit1),
        .alloc_exec_unit2(rename_exec_unit2),
        .alloc_alu_op1(rename_alu_op1),
        .alloc_alu_op2(rename_alu_op2),
        .alloc_branch_op1(rename_branch_op1),
        .alloc_branch_op2(rename_branch_op2),
        .alloc_mem_op1(rename_mem_op1),
        .alloc_mem_op2(rename_mem_op2),
        .alloc_rob_id1(rename_rob_id1),
        .alloc_rob_id2(rename_rob_id2),
        .alloc_valid1(rename_valid1),
        .alloc_valid2(rename_valid2),
        
        .allocated_rs_id1(rs_allocated_id1),
        .allocated_rs_id2(rs_allocated_id2),
        .allocation_success1(rs_allocation_success1),
        .allocation_success2(rs_allocation_success2),
        
        // Register file interface
        .regfile_read_addr1(regfile_read_addr1),
        .regfile_read_addr2(regfile_read_addr2),
        .regfile_read_addr3(regfile_read_addr3),
        .regfile_read_addr4(regfile_read_addr4),
        .regfile_read_enable1(regfile_read_enable1),
        .regfile_read_enable2(regfile_read_enable2),
        .regfile_read_enable3(regfile_read_enable3),
        .regfile_read_enable4(regfile_read_enable4),
        .regfile_read_data1(regfile_read_data1),
        .regfile_read_data2(regfile_read_data2),
        .regfile_read_data3(regfile_read_data3),
        .regfile_read_data4(regfile_read_data4),
        
        // Register ready interface
        .regfile_ready_addr1(regfile_ready_addr1),
        .regfile_ready_addr2(regfile_ready_addr2),
        .regfile_ready_out1(regfile_ready_out1),
        .regfile_ready_out2(regfile_ready_out2),
        
        // Wakeup interface
        .wakeup_tag1(wakeup_tag1),
        .wakeup_tag2(wakeup_tag2),
        .wakeup_valid1(wakeup_valid1),
        .wakeup_valid2(wakeup_valid2),
        
        // Issue interface
        .issue_pc1(exec_pc1),
        .issue_pc2(exec_pc2),
        .issue_instruction1(exec_instruction1),
        .issue_instruction2(exec_instruction2),
        .issue_operand1_1(exec_operand1_1),
        .issue_operand2_1(exec_operand2_1),
        .issue_operand1_2(exec_operand1_2),
        .issue_operand2_2(exec_operand2_2),
        .issue_phys_rd_1(exec_phys_rd_1),
        .issue_phys_rd_2(exec_phys_rd_2),
        .issue_arch_rd_1(exec_arch_rd_1),
        .issue_arch_rd_2(exec_arch_rd_2),
        .issue_immediate1(exec_immediate1),
        .issue_immediate2(exec_immediate2),
        .issue_inst_type1(exec_inst_type1),
        .issue_inst_type2(exec_inst_type2),
        .issue_exec_unit1(exec_exec_unit1),
        .issue_exec_unit2(exec_exec_unit2),
        .issue_alu_op1(exec_alu_op1),
        .issue_alu_op2(exec_alu_op2),
        .issue_branch_op1(exec_branch_op1),
        .issue_branch_op2(exec_branch_op2),
        .issue_mem_op1(exec_mem_op1),
        .issue_mem_op2(exec_mem_op2),
        .issue_rob_id1(exec_rob_id1),
        .issue_rob_id2(exec_rob_id2),
        .issue_rs_id1(rs_issue_rs_id1),
        .issue_rs_id2(rs_issue_rs_id2),
        .issue_valid1(exec_valid1),
        .issue_valid2(exec_valid2),
        
        // Pipeline control
        .stall_issue(stall_scheduler),
        .flush_rs(flush_scheduler),
        .rs_stall_req(rs_stall_req),
        
        // Status outputs
        .rs_entries_used(rs_entries_used),
        .rs_full(rs_full),
        .rs_empty(rs_empty)
    );
    
    // =============================================================================
    // Scheduler Control Logic
    // =============================================================================
    
    assign scheduler_stall_req = rs_stall_req || !exec_ready;
    assign rename_ready = !rs_full && exec_ready;

endmodule