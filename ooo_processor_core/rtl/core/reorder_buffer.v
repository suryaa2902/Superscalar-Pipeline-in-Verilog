// =============================================================================
// Reorder Buffer (ROB)
// =============================================================================
// File: reorder_buffer.v
// Description: Reorder buffer and commit stage for out-of-order processor
// Author: Suryaa Senthilkumar Shanthi
// Date: 10 July 2025
// =============================================================================

`include "ooo_processor_defines.vh"

// =============================================================================
// ROB Controller
// =============================================================================
// Manages instruction allocation, completion, and commit in program order

module rob_controller (
    input wire clk,
    input wire rst_n,
    
    // Allocation interface (from rename stage)
    input wire allocate_req1,
    input wire allocate_req2,
    input wire [`XLEN-1:0] alloc_pc1,
    input wire [`XLEN-1:0] alloc_pc2,
    input wire [4:0] alloc_arch_reg1,
    input wire [4:0] alloc_arch_reg2,
    input wire [`PHYS_REG_BITS-1:0] alloc_phys_reg1,
    input wire [`PHYS_REG_BITS-1:0] alloc_phys_reg2,
    input wire [31:0] alloc_instruction1,
    input wire [31:0] alloc_instruction2,
    input wire [1:0] alloc_exec_unit1,
    input wire [1:0] alloc_exec_unit2,
    input wire alloc_is_branch1,
    input wire alloc_is_branch2,
    input wire alloc_is_store1,
    input wire alloc_is_store2,
    
    output wire [`ROB_ADDR_BITS-1:0] allocated_rob_id1,
    output wire [`ROB_ADDR_BITS-1:0] allocated_rob_id2,
    output wire allocation_valid1,
    output wire allocation_valid2,
    
    // Completion interface (from execution units)
    input wire [`ROB_ADDR_BITS-1:0] complete_rob_id1,
    input wire [`ROB_ADDR_BITS-1:0] complete_rob_id2,
    input wire [`XLEN-1:0] complete_result1,
    input wire [`XLEN-1:0] complete_result2,
    input wire complete_valid1,
    input wire complete_valid2,
    input wire complete_exception1,
    input wire complete_exception2,
    input wire [3:0] complete_exception_code1,
    input wire [3:0] complete_exception_code2,
    input wire complete_branch_taken1,
    input wire complete_branch_taken2,
    input wire [`XLEN-1:0] complete_branch_target1,
    input wire [`XLEN-1:0] complete_branch_target2,
    input wire complete_branch_mispredicted1,
    input wire complete_branch_mispredicted2,
    
    // Commit interface (to commit stage)
    output wire [`ROB_ADDR_BITS-1:0] commit_rob_id1,
    output wire [`ROB_ADDR_BITS-1:0] commit_rob_id2,
    output wire [`XLEN-1:0] commit_pc1,
    output wire [`XLEN-1:0] commit_pc2,
    output wire [4:0] commit_arch_reg1,
    output wire [4:0] commit_arch_reg2,
    output wire [`PHYS_REG_BITS-1:0] commit_phys_reg1,
    output wire [`PHYS_REG_BITS-1:0] commit_phys_reg2,
    output wire [`XLEN-1:0] commit_result1,
    output wire [`XLEN-1:0] commit_result2,
    output wire [31:0] commit_instruction1,
    output wire [31:0] commit_instruction2,
    output wire commit_valid1,
    output wire commit_valid2,
    output wire commit_exception1,
    output wire commit_exception2,
    output wire [3:0] commit_exception_code1,
    output wire [3:0] commit_exception_code2,
    output wire commit_is_branch1,
    output wire commit_is_branch2,
    output wire commit_branch_taken1,
    output wire commit_branch_taken2,
    output wire [`XLEN-1:0] commit_branch_target1,
    output wire [`XLEN-1:0] commit_branch_target2,
    output wire commit_branch_mispredicted1,
    output wire commit_branch_mispredicted2,
    output wire commit_is_store1,
    output wire commit_is_store2,
    
    // Flush interface (for branch misprediction recovery)
    input wire flush_enable,
    input wire [`ROB_ADDR_BITS-1:0] flush_rob_id,
    
    // Status outputs
    output wire [`ROB_ADDR_BITS:0] rob_entries_used,
    output wire rob_full,
    output wire rob_empty,
    
    // Debug interface
    output wire [`ROB_ADDR_BITS-1:0] debug_head_ptr,
    output wire [`ROB_ADDR_BITS-1:0] debug_tail_ptr
);

    // =============================================================================
    // ROB Entry Structure (flattened for Verilog)
    // =============================================================================
    
    // Entry fields (one array per field to avoid 2D arrays)
    reg [`XLEN-1:0]         rob_pc          [`ROB_SIZE-1:0];
    reg [4:0]               rob_arch_reg    [`ROB_SIZE-1:0];
    reg [`PHYS_REG_BITS-1:0] rob_phys_reg   [`ROB_SIZE-1:0];
    reg [`XLEN-1:0]         rob_result      [`ROB_SIZE-1:0];
    reg [31:0]              rob_instruction [`ROB_SIZE-1:0];
    reg [1:0]               rob_exec_unit   [`ROB_SIZE-1:0];
    reg                     rob_ready       [`ROB_SIZE-1:0];
    reg                     rob_valid       [`ROB_SIZE-1:0];
    reg                     rob_exception   [`ROB_SIZE-1:0];
    reg [3:0]               rob_exception_code [`ROB_SIZE-1:0];
    reg                     rob_is_branch   [`ROB_SIZE-1:0];
    reg                     rob_branch_taken [`ROB_SIZE-1:0];
    reg [`XLEN-1:0]         rob_branch_target [`ROB_SIZE-1:0];
    reg                     rob_branch_mispredicted [`ROB_SIZE-1:0];
    reg                     rob_is_store    [`ROB_SIZE-1:0];
    
    // =============================================================================
    // ROB Management Pointers
    // =============================================================================
    
    reg [`ROB_ADDR_BITS-1:0] head_ptr;      // Points to oldest instruction
    reg [`ROB_ADDR_BITS-1:0] tail_ptr;      // Points to next allocation slot
    reg [`ROB_ADDR_BITS:0]   entry_count;   // Number of valid entries
    
    // =============================================================================
    // Allocation Logic
    // =============================================================================
    
    wire can_allocate1, can_allocate2;
    wire [`ROB_ADDR_BITS-1:0] next_tail1, next_tail2;
    
    assign can_allocate1 = (entry_count < `ROB_SIZE) && allocate_req1;
    assign can_allocate2 = (entry_count < (`ROB_SIZE - 1)) && allocate_req2 && can_allocate1;
    
    assign next_tail1 = (tail_ptr + 1) % `ROB_SIZE;
    assign next_tail2 = (tail_ptr + 2) % `ROB_SIZE;
    
    assign allocated_rob_id1 = tail_ptr;
    assign allocated_rob_id2 = next_tail1;
    assign allocation_valid1 = can_allocate1;
    assign allocation_valid2 = can_allocate2;
    
    // =============================================================================
    // Commit Logic
    // =============================================================================
    
    wire can_commit1, can_commit2;
    wire [`ROB_ADDR_BITS-1:0] next_head1, next_head2;
    
    assign can_commit1 = (entry_count > 0) && rob_valid[head_ptr] && rob_ready[head_ptr];
    assign can_commit2 = (entry_count > 1) && rob_valid[next_head1] && rob_ready[next_head1] && can_commit1;
    
    assign next_head1 = (head_ptr + 1) % `ROB_SIZE;
    assign next_head2 = (head_ptr + 2) % `ROB_SIZE;
    
    // Commit outputs
    assign commit_rob_id1 = head_ptr;
    assign commit_rob_id2 = next_head1;
    assign commit_pc1 = rob_pc[head_ptr];
    assign commit_pc2 = rob_pc[next_head1];
    assign commit_arch_reg1 = rob_arch_reg[head_ptr];
    assign commit_arch_reg2 = rob_arch_reg[next_head1];
    assign commit_phys_reg1 = rob_phys_reg[head_ptr];
    assign commit_phys_reg2 = rob_phys_reg[next_head1];
    assign commit_result1 = rob_result[head_ptr];
    assign commit_result2 = rob_result[next_head1];
    assign commit_instruction1 = rob_instruction[head_ptr];
    assign commit_instruction2 = rob_instruction[next_head1];
    assign commit_valid1 = can_commit1;
    assign commit_valid2 = can_commit2;
    assign commit_exception1 = rob_exception[head_ptr];
    assign commit_exception2 = rob_exception[next_head1];
    assign commit_exception_code1 = rob_exception_code[head_ptr];
    assign commit_exception_code2 = rob_exception_code[next_head1];
    assign commit_is_branch1 = rob_is_branch[head_ptr];
    assign commit_is_branch2 = rob_is_branch[next_head1];
    assign commit_branch_taken1 = rob_branch_taken[head_ptr];
    assign commit_branch_taken2 = rob_branch_taken[next_head1];
    assign commit_branch_target1 = rob_branch_target[head_ptr];
    assign commit_branch_target2 = rob_branch_target[next_head1];
    assign commit_branch_mispredicted1 = rob_branch_mispredicted[head_ptr];
    assign commit_branch_mispredicted2 = rob_branch_mispredicted[next_head1];
    assign commit_is_store1 = rob_is_store[head_ptr];
    assign commit_is_store2 = rob_is_store[next_head1];
    
    // =============================================================================
    // Status Outputs
    // =============================================================================
    
    assign rob_entries_used = entry_count;
    assign rob_full = (entry_count >= `ROB_SIZE);
    assign rob_empty = (entry_count == 0);
    assign debug_head_ptr = head_ptr;
    assign debug_tail_ptr = tail_ptr;
    
    // =============================================================================
    // ROB State Management
    // =============================================================================
    
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize ROB
            head_ptr <= {`ROB_ADDR_BITS{1'b0}};
            tail_ptr <= {`ROB_ADDR_BITS{1'b0}};
            entry_count <= {(`ROB_ADDR_BITS+1){1'b0}};
            
            for (i = 0; i < `ROB_SIZE; i = i + 1) begin
                rob_pc[i] <= {`XLEN{1'b0}};
                rob_arch_reg[i] <= 5'b0;
                rob_phys_reg[i] <= {`PHYS_REG_BITS{1'b0}};
                rob_result[i] <= {`XLEN{1'b0}};
                rob_instruction[i] <= 32'b0;
                rob_exec_unit[i] <= 2'b0;
                rob_ready[i] <= 1'b0;
                rob_valid[i] <= 1'b0;
                rob_exception[i] <= 1'b0;
                rob_exception_code[i] <= 4'b0;
                rob_is_branch[i] <= 1'b0;
                rob_branch_taken[i] <= 1'b0;
                rob_branch_target[i] <= {`XLEN{1'b0}};
                rob_branch_mispredicted[i] <= 1'b0;
                rob_is_store[i] <= 1'b0;
            end
        end
        else begin
            // Handle flush (branch misprediction recovery)
            if (flush_enable) begin
                // Flush all entries after flush_rob_id
                for (i = 0; i < `ROB_SIZE; i = i + 1) begin
                    if (((i > flush_rob_id) && (i < tail_ptr)) || 
                        ((tail_ptr < head_ptr) && ((i > flush_rob_id) || (i < tail_ptr)))) begin
                        rob_valid[i] <= 1'b0;
                        rob_ready[i] <= 1'b0;
                    end
                end
                
                // Update tail pointer
                tail_ptr <= (flush_rob_id + 1) % `ROB_SIZE;
                
                // Update entry count
                if (flush_rob_id >= head_ptr) begin
                    entry_count <= flush_rob_id - head_ptr + 1;
                end else begin
                    entry_count <= `ROB_SIZE - head_ptr + flush_rob_id + 1;
                end
            end
            else begin
                // Handle allocations
                if (can_allocate1) begin
                    rob_pc[tail_ptr] <= alloc_pc1;
                    rob_arch_reg[tail_ptr] <= alloc_arch_reg1;
                    rob_phys_reg[tail_ptr] <= alloc_phys_reg1;
                    rob_instruction[tail_ptr] <= alloc_instruction1;
                    rob_exec_unit[tail_ptr] <= alloc_exec_unit1;
                    rob_is_branch[tail_ptr] <= alloc_is_branch1;
                    rob_is_store[tail_ptr] <= alloc_is_store1;
                    rob_valid[tail_ptr] <= 1'b1;
                    rob_ready[tail_ptr] <= 1'b0;
                    rob_exception[tail_ptr] <= 1'b0;
                    rob_branch_mispredicted[tail_ptr] <= 1'b0;
                    
                    tail_ptr <= next_tail1;
                    entry_count <= entry_count + 1;
                end
                
                if (can_allocate2) begin
                    rob_pc[next_tail1] <= alloc_pc2;
                    rob_arch_reg[next_tail1] <= alloc_arch_reg2;
                    rob_phys_reg[next_tail1] <= alloc_phys_reg2;
                    rob_instruction[next_tail1] <= alloc_instruction2;
                    rob_exec_unit[next_tail1] <= alloc_exec_unit2;
                    rob_is_branch[next_tail1] <= alloc_is_branch2;
                    rob_is_store[next_tail1] <= alloc_is_store2;
                    rob_valid[next_tail1] <= 1'b1;
                    rob_ready[next_tail1] <= 1'b0;
                    rob_exception[next_tail1] <= 1'b0;
                    rob_branch_mispredicted[next_tail1] <= 1'b0;
                    
                    tail_ptr <= next_tail2;
                    entry_count <= entry_count + 1;
                end
                
                // Handle completions
                if (complete_valid1 && rob_valid[complete_rob_id1]) begin
                    rob_result[complete_rob_id1] <= complete_result1;
                    rob_ready[complete_rob_id1] <= 1'b1;
                    rob_exception[complete_rob_id1] <= complete_exception1;
                    rob_exception_code[complete_rob_id1] <= complete_exception_code1;
                    rob_branch_taken[complete_rob_id1] <= complete_branch_taken1;
                    rob_branch_target[complete_rob_id1] <= complete_branch_target1;
                    rob_branch_mispredicted[complete_rob_id1] <= complete_branch_mispredicted1;
                end
                
                if (complete_valid2 && rob_valid[complete_rob_id2]) begin
                    rob_result[complete_rob_id2] <= complete_result2;
                    rob_ready[complete_rob_id2] <= 1'b1;
                    rob_exception[complete_rob_id2] <= complete_exception2;
                    rob_exception_code[complete_rob_id2] <= complete_exception_code2;
                    rob_branch_taken[complete_rob_id2] <= complete_branch_taken2;
                    rob_branch_target[complete_rob_id2] <= complete_branch_target2;
                    rob_branch_mispredicted[complete_rob_id2] <= complete_branch_mispredicted2;
                end
                
                // Handle commits
                if (can_commit1) begin
                    rob_valid[head_ptr] <= 1'b0;
                    rob_ready[head_ptr] <= 1'b0;
                    head_ptr <= next_head1;
                    entry_count <= entry_count - 1;
                end
                
                if (can_commit2) begin
                    rob_valid[next_head1] <= 1'b0;
                    rob_ready[next_head1] <= 1'b0;
                    head_ptr <= next_head2;
                    entry_count <= entry_count - 1;
                end
            end
        end
    end

endmodule

// =============================================================================
// Commit Stage
// =============================================================================
// Handles in-order commit of instructions and architectural state updates

module commit_stage (
    input wire clk,
    input wire rst_n,
    
    // Input from ROB
    input wire [`ROB_ADDR_BITS-1:0] rob_commit_id1,
    input wire [`ROB_ADDR_BITS-1:0] rob_commit_id2,
    input wire [`XLEN-1:0] rob_commit_pc1,
    input wire [`XLEN-1:0] rob_commit_pc2,
    input wire [4:0] rob_commit_arch_reg1,
    input wire [4:0] rob_commit_arch_reg2,
    input wire [`PHYS_REG_BITS-1:0] rob_commit_phys_reg1,
    input wire [`PHYS_REG_BITS-1:0] rob_commit_phys_reg2,
    input wire [`XLEN-1:0] rob_commit_result1,
    input wire [`XLEN-1:0] rob_commit_result2,
    input wire [31:0] rob_commit_instruction1,
    input wire [31:0] rob_commit_instruction2,
    input wire rob_commit_valid1,
    input wire rob_commit_valid2,
    input wire rob_commit_exception1,
    input wire rob_commit_exception2,
    input wire [3:0] rob_commit_exception_code1,
    input wire [3:0] rob_commit_exception_code2,
    input wire rob_commit_is_branch1,
    input wire rob_commit_is_branch2,
    input wire rob_commit_branch_taken1,
    input wire rob_commit_branch_taken2,
    input wire [`XLEN-1:0] rob_commit_branch_target1,
    input wire [`XLEN-1:0] rob_commit_branch_target2,
    input wire rob_commit_branch_mispredicted1,
    input wire rob_commit_branch_mispredicted2,
    input wire rob_commit_is_store1,
    input wire rob_commit_is_store2,
    
    // Register file writeback interface
    output wire [`PHYS_REG_BITS-1:0] regfile_write_addr1,
    output wire [`PHYS_REG_BITS-1:0] regfile_write_addr2,
    output wire [`XLEN-1:0] regfile_write_data1,
    output wire [`XLEN-1:0] regfile_write_data2,
    output wire regfile_write_enable1,
    output wire regfile_write_enable2,
    
    // RAT update interface (architectural state)
    output wire [4:0] rat_commit_arch_reg1,
    output wire [4:0] rat_commit_arch_reg2,
    output wire [`PHYS_REG_BITS-1:0] rat_commit_phys_reg1,
    output wire [`PHYS_REG_BITS-1:0] rat_commit_phys_reg2,
    output wire rat_commit_enable1,
    output wire rat_commit_enable2,
    
    // Free list interface (return old physical registers)
    output wire [`PHYS_REG_BITS-1:0] free_list_return_reg1,
    output wire [`PHYS_REG_BITS-1:0] free_list_return_reg2,
    output wire free_list_return_enable1,
    output wire free_list_return_enable2,
    
    // Branch prediction update interface
    output wire [`XLEN-1:0] bp_update_pc1,
    output wire [`XLEN-1:0] bp_update_pc2,
    output wire bp_update_taken1,
    output wire bp_update_taken2,
    output wire [`XLEN-1:0] bp_update_target1,
    output wire [`XLEN-1:0] bp_update_target2,
    output wire bp_update_valid1,
    output wire bp_update_valid2,
    
    // Exception handling interface
    output wire exception_occurred,
    output wire [3:0] exception_code,
    output wire [`XLEN-1:0] exception_pc,
    output wire [`XLEN-1:0] exception_instruction,
    
    // Branch misprediction interface
    output wire branch_misprediction,
    output wire [`XLEN-1:0] branch_correct_target,
    output wire [`ROB_ADDR_BITS-1:0] branch_rob_id,
    
    // Store commit interface
    output wire [`XLEN-1:0] store_commit_pc1,
    output wire [`XLEN-1:0] store_commit_pc2,
    output wire store_commit_valid1,
    output wire store_commit_valid2,
    
    // Performance counters
    output reg [`XLEN-1:0] committed_instructions,
    output reg [`XLEN-1:0] committed_branches,
    output reg [`XLEN-1:0] committed_stores,
    output reg [`XLEN-1:0] branch_mispredictions
);

    // =============================================================================
    // Register File Writeback
    // =============================================================================
    
    assign regfile_write_addr1 = rob_commit_phys_reg1;
    assign regfile_write_addr2 = rob_commit_phys_reg2;
    assign regfile_write_data1 = rob_commit_result1;
    assign regfile_write_data2 = rob_commit_result2;
    assign regfile_write_enable1 = rob_commit_valid1 && !rob_commit_exception1 && !`IS_REG_ZERO(rob_commit_arch_reg1);
    assign regfile_write_enable2 = rob_commit_valid2 && !rob_commit_exception2 && !`IS_REG_ZERO(rob_commit_arch_reg2);
    
    // =============================================================================
    // RAT Architectural Update
    // =============================================================================
    
    assign rat_commit_arch_reg1 = rob_commit_arch_reg1;
    assign rat_commit_arch_reg2 = rob_commit_arch_reg2;
    assign rat_commit_phys_reg1 = rob_commit_phys_reg1;
    assign rat_commit_phys_reg2 = rob_commit_phys_reg2;
    assign rat_commit_enable1 = rob_commit_valid1 && !rob_commit_exception1 && !`IS_REG_ZERO(rob_commit_arch_reg1);
    assign rat_commit_enable2 = rob_commit_valid2 && !rob_commit_exception2 && !`IS_REG_ZERO(rob_commit_arch_reg2);
    
    // =============================================================================
    // Free List Management
    // =============================================================================
    
    // TODO: Need to track old physical registers to return them to free list
    // This requires additional state or interface from rename stage
    assign free_list_return_reg1 = {`PHYS_REG_BITS{1'b0}};
    assign free_list_return_reg2 = {`PHYS_REG_BITS{1'b0}};
    assign free_list_return_enable1 = 1'b0;
    assign free_list_return_enable2 = 1'b0;
    
    // =============================================================================
    // Branch Prediction Update
    // =============================================================================
    
    assign bp_update_pc1 = rob_commit_pc1;
    assign bp_update_pc2 = rob_commit_pc2;
    assign bp_update_taken1 = rob_commit_branch_taken1;
    assign bp_update_taken2 = rob_commit_branch_taken2;
    assign bp_update_target1 = rob_commit_branch_target1;
    assign bp_update_target2 = rob_commit_branch_target2;
    assign bp_update_valid1 = rob_commit_valid1 && rob_commit_is_branch1;
    assign bp_update_valid2 = rob_commit_valid2 && rob_commit_is_branch2;
    
    // =============================================================================
    // Exception Handling
    // =============================================================================
    
    // Priority: instruction 1 exceptions take priority over instruction 2
    assign exception_occurred = (rob_commit_valid1 && rob_commit_exception1) || 
                               (rob_commit_valid2 && rob_commit_exception2 && !rob_commit_exception1);
    assign exception_code = rob_commit_exception1 ? rob_commit_exception_code1 : rob_commit_exception_code2;
    assign exception_pc = rob_commit_exception1 ? rob_commit_pc1 : rob_commit_pc2;
    assign exception_instruction = rob_commit_exception1 ? rob_commit_instruction1 : rob_commit_instruction2;
    
    // =============================================================================
    // Branch Misprediction Handling
    // =============================================================================
    
    assign branch_misprediction = (rob_commit_valid1 && rob_commit_branch_mispredicted1) || 
                                 (rob_commit_valid2 && rob_commit_branch_mispredicted2);
    assign branch_correct_target = rob_commit_branch_mispredicted1 ? rob_commit_branch_target1 : rob_commit_branch_target2;
    assign branch_rob_id = rob_commit_branch_mispredicted1 ? rob_commit_id1 : rob_commit_id2;
    
    // =============================================================================
    // Store Commit Interface
    // =============================================================================
    
    assign store_commit_pc1 = rob_commit_pc1;
    assign store_commit_pc2 = rob_commit_pc2;
    assign store_commit_valid1 = rob_commit_valid1 && rob_commit_is_store1;
    assign store_commit_valid2 = rob_commit_valid2 && rob_commit_is_store2;
    
    // =============================================================================
    // Performance Counters
    // =============================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            committed_instructions <= {`XLEN{1'b0}};
            committed_branches <= {`XLEN{1'b0}};
            committed_stores <= {`XLEN{1'b0}};
            branch_mispredictions <= {`XLEN{1'b0}};
        end
        else begin
            // Count committed instructions
            if (rob_commit_valid1 && rob_commit_valid2) begin
                committed_instructions <= committed_instructions + 2;
            end
            else if (rob_commit_valid1) begin
                committed_instructions <= committed_instructions + 1;
            end
            
            // Count committed branches
            if (rob_commit_valid1 && rob_commit_is_branch1) begin
                committed_branches <= committed_branches + 1;
            end
            if (rob_commit_valid2 && rob_commit_is_branch2) begin
                committed_branches <= committed_branches + 1;
            end
            
            // Count committed stores
            if (rob_commit_valid1 && rob_commit_is_store1) begin
                committed_stores <= committed_stores + 1;
            end
            if (rob_commit_valid2 && rob_commit_is_store2) begin
                committed_stores <= committed_stores + 1;
            end
            
            // Count branch mispredictions
            if (rob_commit_valid1 && rob_commit_branch_mispredicted1) begin
                branch_mispredictions <= branch_mispredictions + 1;
            end
            if (rob_commit_valid2 && rob_commit_branch_mispredicted2) begin
                branch_mispredictions <= branch_mispredictions + 1;
            end
        end
    end

endmodule