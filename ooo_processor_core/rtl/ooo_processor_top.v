// =============================================================================
// Out-of-Order Processor Top Level
// =============================================================================
// File: ooo_processor_top.v
// Description: Complete out-of-order superscalar processor integration
// Author: Suryaa Senthilkumar Shanthi
// Date: 20 June 2025
// =============================================================================

`include "ooo_processor_defines.vh"

module ooo_processor_top (
    input wire clk,
    input wire rst_n,
    
    // External memory interface (simplified)
    output wire [31:0] imem_addr,
    output wire imem_req,
    input wire [63:0] imem_data,
    input wire imem_valid,
    input wire imem_ready,
    
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0] dmem_be,
    output wire dmem_we,
    output wire dmem_req,
    input wire [31:0] dmem_rdata,
    input wire dmem_valid,
    input wire dmem_ready,
    
    // Debug and status outputs
    output wire [`XLEN-1:0] debug_pc,
    output wire [31:0] debug_instruction,
    output wire debug_instruction_valid,
    output wire [31:0] committed_instructions,
    output wire processor_idle,
    
    // Performance monitoring
    output wire [31:0] total_cycles,
    output wire [31:0] stall_cycles,
    output wire [31:0] flush_cycles
);

    // =============================================================================
    // Global Control Signals
    // =============================================================================
    
    wire global_stall, global_flush;
    wire recovery_mode;
    wire [`XLEN-1:0] recovery_pc;
    
    // Pipeline control signals
    wire stall_fetch, stall_decode, stall_rename, stall_issue, stall_execute;
    wire flush_fetch, flush_decode, flush_rename, flush_issue, flush_execute;
    
    // =============================================================================
    // Fetch Stage Signals
    // =============================================================================
    
    // Fetch unit outputs
    wire [`XLEN-1:0] fetch_pc1, fetch_pc2;
    wire [31:0] fetch_instruction1, fetch_instruction2;
    wire fetch_valid1, fetch_valid2;
    wire fetch_predicted_taken1, fetch_predicted_taken2;
    wire [`XLEN-1:0] fetch_predicted_target1, fetch_predicted_target2;
    wire fetch_stall_req;
    
    // Branch prediction
    wire [`XLEN-1:0] bp_fetch_pc;
    wire bp_fetch_req, bp_prediction, bp_valid;
    wire [`XLEN-1:0] bp_target;
    
    // Branch updates from commit
    wire [`XLEN-1:0] bp_update_pc1, bp_update_pc2;
    wire bp_update_taken1, bp_update_taken2;
    wire [`XLEN-1:0] bp_update_target1, bp_update_target2;
    wire bp_update_valid1, bp_update_valid2;
    
    // Fetch queue outputs
    wire [`XLEN-1:0] decode_pc1, decode_pc2;
    wire [31:0] decode_instruction1, decode_instruction2;
    wire decode_valid1, decode_valid2;
    wire decode_predicted_taken1, decode_predicted_taken2;
    wire [`XLEN-1:0] decode_predicted_target1, decode_predicted_target2;
    wire fetch_queue_full, fetch_queue_empty;
    wire decode_ready, fetch_ready;
    
    // =============================================================================
    // Decode Stage Signals
    // =============================================================================
    
    wire [4:0] decode_rs1_1, decode_rs2_1, decode_rd_1;
    wire [4:0] decode_rs1_2, decode_rs2_2, decode_rd_2;
    wire [31:0] decode_immediate1, decode_immediate2;
    wire [2:0] decode_inst_type1, decode_inst_type2;
    wire [1:0] decode_exec_unit1, decode_exec_unit2;
    wire [3:0] decode_alu_op1, decode_alu_op2;
    wire [2:0] decode_branch_op1, decode_branch_op2;
    wire [2:0] decode_mem_op1, decode_mem_op2;
    wire decode_uses_rs1_1, decode_uses_rs2_1, decode_writes_rd_1;
    wire decode_uses_rs1_2, decode_uses_rs2_2, decode_writes_rd_2;
    wire decode_is_branch1, decode_is_branch2;
    wire decode_is_load1, decode_is_load2;
    wire decode_is_store1, decode_is_store2;
    wire decode_exception1, decode_exception2;
    wire [3:0] decode_exception_code1, decode_exception_code2;
    wire decode_stall_req;
    
    // =============================================================================
    // Rename Stage Signals
    // =============================================================================
    
    wire [`PHYS_REG_BITS-1:0] rename_phys_rs1_1, rename_phys_rs2_1, rename_phys_rd_1;
    wire [`PHYS_REG_BITS-1:0] rename_phys_rs1_2, rename_phys_rs2_2, rename_phys_rd_2;
    wire [`ROB_ADDR_BITS-1:0] rename_rob_id1, rename_rob_id2;
    wire rename_valid1, rename_valid2;
    wire rename_stall_req;
    
    // RAT interfaces
    wire [4:0] rat_lookup_rs1_1, rat_lookup_rs2_1, rat_lookup_rs1_2, rat_lookup_rs2_2;
    wire rat_lookup_enable1, rat_lookup_enable2, rat_lookup_enable3, rat_lookup_enable4;
    wire [`PHYS_REG_BITS-1:0] rat_phys_rs1_1, rat_phys_rs2_1, rat_phys_rs1_2, rat_phys_rs2_2;
    wire rat_valid1, rat_valid2, rat_valid3, rat_valid4;
    
    wire [4:0] rat_update_arch_reg1, rat_update_arch_reg2;
    wire [`PHYS_REG_BITS-1:0] rat_update_phys_reg1, rat_update_phys_reg2;
    wire rat_update_enable1, rat_update_enable2;
    
    // Free list interfaces
    wire free_list_allocate_req1, free_list_allocate_req2;
    wire [`PHYS_REG_BITS-1:0] free_list_allocated_reg1, free_list_allocated_reg2;
    wire free_list_allocation_valid1, free_list_allocation_valid2;
    
    // ROB allocation
    wire rob_allocate_req1, rob_allocate_req2;
    wire [`ROB_ADDR_BITS-1:0] rob_allocated_id1, rob_allocated_id2;
    wire rob_allocation_valid1, rob_allocation_valid2;
    
    // =============================================================================
    // Reservation Station Signals
    // =============================================================================
    
    wire [`XLEN-1:0] exec_pc1, exec_pc2;
    wire [31:0] exec_instruction1, exec_instruction2;
    wire [`XLEN-1:0] exec_operand1_1, exec_operand2_1;
    wire [`XLEN-1:0] exec_operand1_2, exec_operand2_2;
    wire [`PHYS_REG_BITS-1:0] exec_phys_rd_1, exec_phys_rd_2;
    wire [4:0] exec_arch_rd_1, exec_arch_rd_2;
    wire [31:0] exec_immediate1, exec_immediate2;
    wire [2:0] exec_inst_type1, exec_inst_type2;
    wire [1:0] exec_exec_unit1, exec_exec_unit2;
    wire [3:0] exec_alu_op1, exec_alu_op2;
    wire [2:0] exec_branch_op1, exec_branch_op2;
    wire [2:0] exec_mem_op1, exec_mem_op2;
    wire [`ROB_ADDR_BITS-1:0] exec_rob_id1, exec_rob_id2;
    wire exec_valid1, exec_valid2;
    wire scheduler_stall_req;
    
    // Register file interfaces
    wire [`PHYS_REG_BITS-1:0] regfile_read_addr1, regfile_read_addr2;
    wire [`PHYS_REG_BITS-1:0] regfile_read_addr3, regfile_read_addr4;
    wire regfile_read_enable1, regfile_read_enable2, regfile_read_enable3, regfile_read_enable4;
    wire [`XLEN-1:0] regfile_read_data1, regfile_read_data2;
    wire [`XLEN-1:0] regfile_read_data3, regfile_read_data4;
    
    wire [`PHYS_REG_BITS-1:0] regfile_ready_addr1, regfile_ready_addr2;
    wire regfile_ready_out1, regfile_ready_out2;
    
    // Wakeup signals (simplified - from execution units)
    wire [`PHYS_REG_BITS-1:0] wakeup_tag1, wakeup_tag2;
    wire wakeup_valid1, wakeup_valid2;
    
    // =============================================================================
    // Execution Unit Signals
    // =============================================================================
    
    // ALU results
    wire [`XLEN-1:0] alu_result_pc;
    wire [31:0] alu_result_instruction;
    wire [`XLEN-1:0] alu_result;
    wire [`PHYS_REG_BITS-1:0] alu_result_phys_rd;
    wire [4:0] alu_result_arch_rd;
    wire [`ROB_ADDR_BITS-1:0] alu_result_rob_id;
    wire alu_result_valid, alu_exception;
    wire [3:0] alu_exception_code;
    
    // Branch results
    wire [`XLEN-1:0] branch_result_pc;
    wire [31:0] branch_result_instruction;
    wire [`XLEN-1:0] branch_result;
    wire [`PHYS_REG_BITS-1:0] branch_result_phys_rd;
    wire [4:0] branch_result_arch_rd;
    wire [`ROB_ADDR_BITS-1:0] branch_result_rob_id;
    wire branch_result_valid, branch_taken;
    wire [`XLEN-1:0] branch_target;
    wire branch_mispredicted, branch_exception;
    wire [3:0] branch_exception_code;
    
    // LSU results
    wire [`XLEN-1:0] lsu_result_pc;
    wire [31:0] lsu_result_instruction;
    wire [`XLEN-1:0] lsu_result;
    wire [`PHYS_REG_BITS-1:0] lsu_result_phys_rd;
    wire [4:0] lsu_result_arch_rd;
    wire [`ROB_ADDR_BITS-1:0] lsu_result_rob_id;
    wire lsu_result_valid, lsu_exception;
    wire [3:0] lsu_exception_code;
    
    // =============================================================================
    // ROB and Commit Signals
    // =============================================================================
    
    wire [`ROB_ADDR_BITS-1:0] commit_rob_id1, commit_rob_id2;
    wire [`XLEN-1:0] commit_pc1, commit_pc2;
    wire [4:0] commit_arch_reg1, commit_arch_reg2;
    wire [`PHYS_REG_BITS-1:0] commit_phys_reg1, commit_phys_reg2;
    wire [`XLEN-1:0] commit_result1, commit_result2;
    wire [31:0] commit_instruction1, commit_instruction2;
    wire commit_valid1, commit_valid2;
    wire commit_exception1, commit_exception2;
    wire [3:0] commit_exception_code1, commit_exception_code2;
    wire commit_is_branch1, commit_is_branch2;
    wire commit_branch_taken1, commit_branch_taken2;
    wire [`XLEN-1:0] commit_branch_target1, commit_branch_target2;
    wire commit_branch_mispredicted1, commit_branch_mispredicted2;
    wire commit_is_store1, commit_is_store2;
    
    // Register file writeback
    wire [`PHYS_REG_BITS-1:0] regfile_write_addr1, regfile_write_addr2;
    wire [`XLEN-1:0] regfile_write_data1, regfile_write_data2;
    wire regfile_write_enable1, regfile_write_enable2;
    
    // RAT commit updates
    wire [4:0] rat_commit_arch_reg1, rat_commit_arch_reg2;
    wire [`PHYS_REG_BITS-1:0] rat_commit_phys_reg1, rat_commit_phys_reg2;
    wire rat_commit_enable1, rat_commit_enable2;
    
    // Status signals
    wire [`ROB_ADDR_BITS:0] rob_entries_used;
    wire rob_full, rob_empty;
    wire [`RS_ADDR_BITS:0] rs_entries_used;
    wire rs_full, rs_empty;
    
    // Exception and branch misprediction
    wire exception_occurred;
    wire [3:0] exception_code;
    wire [`XLEN-1:0] exception_pc;
    wire branch_misprediction;
    wire [`XLEN-1:0] branch_correct_target;
    
    // =============================================================================
    // Hazard Detection and Pipeline Control
    // =============================================================================
    
    wire [`PHYS_REG_BITS:0] free_regs_available;
    wire alu_busy, branch_busy, lsu_busy;
    wire dcache_miss, icache_miss;
    
    // Simplified execution unit status
    assign alu_busy = 1'b0;      // Simplified: assume always available
    assign branch_busy = 1'b0;
    assign lsu_busy = 1'b0;
    assign dcache_miss = 1'b0;
    assign icache_miss = 1'b0;
    
    hazard_detection hazard_detect (
        .clk(clk),
        .rst_n(rst_n),
        
        // Status inputs
        .fetch_queue_full(fetch_queue_full),
        .fetch_queue_empty(fetch_queue_empty),
        .decode_stall_req(decode_stall_req),
        .rename_stall_req(rename_stall_req),
        .rs_full(rs_full),
        .rs_empty(rs_empty),
        .rob_full(rob_full),
        .rob_empty(rob_empty),
        .free_list_empty(!free_list_allocation_valid1),
        .rs_entries_used(rs_entries_used),
        .rob_entries_used(rob_entries_used),
        
        // Execution unit status
        .alu_busy(alu_busy),
        .branch_busy(branch_busy),
        .lsu_busy(lsu_busy),
        .dcache_miss(dcache_miss),
        .icache_miss(icache_miss),
        
        // Exception and branch misprediction
        .exception_occurred(exception_occurred),
        .branch_misprediction(branch_misprediction),
        .exception_pc(exception_pc),
        .branch_target_pc(branch_correct_target),
        
        // Output stall signals
        .stall_fetch(stall_fetch),
        .stall_decode(stall_decode),
        .stall_rename(stall_rename),
        .stall_issue(stall_issue),
        .stall_execute(stall_execute),
        
        // Output flush signals
        .flush_fetch(flush_fetch),
        .flush_decode(flush_decode),
        .flush_rename(flush_rename),
        .flush_issue(flush_issue),
        .flush_execute(flush_execute),
        
        // Recovery control
        .recovery_mode(recovery_mode),
        .recovery_pc(recovery_pc),
        
        // Performance monitoring
        .stall_cycles(stall_cycles),
        .flush_cycles(flush_cycles),
        .hazard_count()
    );
    
    // =============================================================================
    // Fetch Stage
    // =============================================================================
    
    instruction_fetch fetch_unit (
        .clk(clk),
        .rst_n(rst_n),
        
        // Memory interface
        .icache_addr(imem_addr),
        .icache_req(imem_req),
        .icache_ready(imem_ready),
        .icache_valid(imem_valid),
        .icache_data(imem_data),
        .icache_error(1'b0),
        
        // Branch prediction
        .bp_fetch_pc(bp_fetch_pc),
        .bp_fetch_req(bp_fetch_req),
        .bp_prediction(bp_prediction),
        .bp_target(bp_target),
        .bp_valid(bp_valid),
        
        // Branch updates
        .bp_update_pc(bp_update_pc1),
        .bp_update_taken(bp_update_taken1),
        .bp_update_target(bp_update_target1),
        .bp_update_valid(bp_update_valid1),
        
        // Branch misprediction recovery
        .branch_misprediction(branch_misprediction),
        .branch_correct_pc(branch_correct_target),
        
        // Exception handling
        .exception_occurred(exception_occurred),
        .exception_vector(32'h00000004), // Simplified exception vector
        
        // Output to fetch queue
        .fetch_pc1(fetch_pc1),
        .fetch_pc2(fetch_pc2),
        .fetch_instruction1(fetch_instruction1),
        .fetch_instruction2(fetch_instruction2),
        .fetch_valid1(fetch_valid1),
        .fetch_valid2(fetch_valid2),
        .fetch_predicted_taken1(fetch_predicted_taken1),
        .fetch_predicted_taken2(fetch_predicted_taken2),
        .fetch_predicted_target1(fetch_predicted_target1),
        .fetch_predicted_target2(fetch_predicted_target2),
        
        // Pipeline control
        .stall_fetch(stall_fetch),
        .flush_fetch(flush_fetch),
        .fetch_stall_req(fetch_stall_req),
        
        // Debug
        .debug_current_pc(debug_pc),
        .debug_fetch_busy()
    );
    
    branch_predictor bp (
        .clk(clk),
        .rst_n(rst_n),
        
        // Prediction interface
        .fetch_pc(bp_fetch_pc),
        .prediction_req(bp_fetch_req),
        .prediction(bp_prediction),
        .predicted_target(bp_target),
        .prediction_valid(bp_valid),
        
        // Update interface
        .update_pc(bp_update_pc1),
        .update_taken(bp_update_taken1),
        .update_target(bp_update_target1),
        .update_valid(bp_update_valid1),
        
        // Debug
        .debug_predictions(),
        .debug_mispredictions()
    );
    
    fetch_queue fq (
        .clk(clk),
        .rst_n(rst_n),
        
        // Input from fetch
        .fetch_pc1(fetch_pc1),
        .fetch_pc2(fetch_pc2),
        .fetch_instruction1(fetch_instruction1),
        .fetch_instruction2(fetch_instruction2),
        .fetch_valid1(fetch_valid1),
        .fetch_valid2(fetch_valid2),
        .fetch_predicted_taken1(fetch_predicted_taken1),
        .fetch_predicted_taken2(fetch_predicted_taken2),
        .fetch_predicted_target1(fetch_predicted_target1),
        .fetch_predicted_target2(fetch_predicted_target2),
        
        // Output to decode
        .decode_pc1(decode_pc1),
        .decode_pc2(decode_pc2),
        .decode_instruction1(decode_instruction1),
        .decode_instruction2(decode_instruction2),
        .decode_valid1(decode_valid1),
        .decode_valid2(decode_valid2),
        .decode_predicted_taken1(decode_predicted_taken1),
        .decode_predicted_taken2(decode_predicted_taken2),
        .decode_predicted_target1(decode_predicted_target1),
        .decode_predicted_target2(decode_predicted_target2),
        
        // Flow control
        .decode_ready(decode_ready),
        .fetch_ready(fetch_ready),
        
        // Pipeline control
        .flush_queue(flush_fetch),
        
        // Status
        .queue_full(fetch_queue_full),
        .queue_empty(fetch_queue_empty),
        .queue_entries()
    );
    
    // =============================================================================
    // Decode Stage
    // =============================================================================
    
    decode_stage decode (
        .clk(clk),
        .rst_n(rst_n),
        
        // Input from fetch queue
        .fetch_pc1(decode_pc1),
        .fetch_pc2(decode_pc2),
        .fetch_instruction1(decode_instruction1),
        .fetch_instruction2(decode_instruction2),
        .fetch_valid1(decode_valid1),
        .fetch_valid2(decode_valid2),
        .fetch_predicted_taken1(decode_predicted_taken1),
        .fetch_predicted_taken2(decode_predicted_taken2),
        .fetch_predicted_target1(decode_predicted_target1),
        .fetch_predicted_target2(decode_predicted_target2),
        
        // Output to rename
        .decode_pc1(decode_pc1),
        .decode_pc2(decode_pc2),
        .decode_instruction1(decode_instruction1),
        .decode_instruction2(decode_instruction2),
        .decode_rs1_1(decode_rs1_1),
        .decode_rs2_1(decode_rs2_1),
        .decode_rd_1(decode_rd_1),
        .decode_rs1_2(decode_rs1_2),
        .decode_rs2_2(decode_rs2_2),
        .decode_rd_2(decode_rd_2),
        .decode_immediate1(decode_immediate1),
        .decode_immediate2(decode_immediate2),
        .decode_inst_type1(decode_inst_type1),
        .decode_inst_type2(decode_inst_type2),
        .decode_exec_unit1(decode_exec_unit1),
        .decode_exec_unit2(decode_exec_unit2),
        .decode_alu_op1(decode_alu_op1),
        .decode_alu_op2(decode_alu_op2),
        .decode_branch_op1(decode_branch_op1),
        .decode_branch_op2(decode_branch_op2),
        .decode_mem_op1(decode_mem_op1),
        .decode_mem_op2(decode_mem_op2),
        .decode_uses_rs1_1(decode_uses_rs1_1),
        .decode_uses_rs2_1(decode_uses_rs2_1),
        .decode_writes_rd_1(decode_writes_rd_1),
        .decode_uses_rs1_2(decode_uses_rs1_2),
        .decode_uses_rs2_2(decode_uses_rs2_2),
        .decode_writes_rd_2(decode_writes_rd_2),
        .decode_is_branch1(decode_is_branch1),
        .decode_is_branch2(decode_is_branch2),
        .decode_is_jump1(),
        .decode_is_jump2(),
        .decode_is_load1(decode_is_load1),
        .decode_is_load2(decode_is_load2),
        .decode_is_store1(decode_is_store1),
        .decode_is_store2(decode_is_store2),
        .decode_predicted_taken1(decode_predicted_taken1),
        .decode_predicted_taken2(decode_predicted_taken2),
        .decode_predicted_target1(decode_predicted_target1),
        .decode_predicted_target2(decode_predicted_target2),
        .decode_valid1(decode_valid1),
        .decode_valid2(decode_valid2),
        
        // Exception interface
        .decode_exception1(decode_exception1),
        .decode_exception2(decode_exception2),
        .decode_exception_code1(decode_exception_code1),
        .decode_exception_code2(decode_exception_code2),
        
        // Pipeline control
        .stall_decode(stall_decode),
        .flush_decode(flush_decode),
        .decode_stall_req(decode_stall_req),
        
        // Flow control
        .rename_ready(!rename_stall_req),
        .fetch_ready(decode_ready)
    );
    
    // =============================================================================
    // Register File and Free List
    // =============================================================================
    
    register_file regfile (
        .clk(clk),
        .rst_n(rst_n),
        
        // Read ports
        .read_addr1(regfile_read_addr1),
        .read_addr2(regfile_read_addr2),
        .read_addr3(regfile_read_addr3),
        .read_addr4(regfile_read_addr4),
        .read_enable1(regfile_read_enable1),
        .read_enable2(regfile_read_enable2),
        .read_enable3(regfile_read_enable3),
        .read_enable4(regfile_read_enable4),
        
        .read_data1(regfile_read_data1),
        .read_data2(regfile_read_data2),
        .read_data3(regfile_read_data3),
        .read_data4(regfile_read_data4),
        
        // Write ports
        .write_addr1(regfile_write_addr1),
        .write_addr2(regfile_write_addr2),
        .write_data1(regfile_write_data1),
        .write_data2(regfile_write_data2),
        .write_enable1(regfile_write_enable1),
        .write_enable2(regfile_write_enable2),
        
        // Register ready bits
        .ready_addr1(regfile_ready_addr1),
        .ready_addr2(regfile_ready_addr2),
        .ready_set1(wakeup_valid1),
        .ready_set2(wakeup_valid2),
        .ready_clear1(1'b0),
        .ready_clear2(1'b0),
        
        .ready_out1(regfile_ready_out1),
        .ready_out2(regfile_ready_out2),
        
        // Free list interface (simplified)
        .free_reg_addr({`PHYS_REG_BITS{1'b0}}),
        .free_reg_enable(1'b0),
        
        // Debug
        .debug_ready_bits()
    );
    
    free_list_manager free_list (
        .clk(clk),
        .rst_n(rst_n),
        
        // Allocation interface
        .allocate_req1(free_list_allocate_req1),
        .allocate_req2(free_list_allocate_req2),
        .allocated_reg1(free_list_allocated_reg1),
        .allocated_reg2(free_list_allocated_reg2),
        .allocation_valid1(free_list_allocation_valid1),
        .allocation_valid2(free_list_allocation_valid2),
        
        // Deallocation interface (simplified)
        .free_reg1({`PHYS_REG_BITS{1'b0}}),
        .free_reg2({`PHYS_REG_BITS{1'b0}}),
        .free_enable1(1'b0),
        .free_enable2(1'b0),
        
        // Status
        .free_count(free_regs_available),
        .free_list_empty(),
        .free_list_full()
    );
    
    // =============================================================================
    // Rename Stage
    // =============================================================================
    
    register_alias_table rat (
        .clk(clk),
        .rst_n(rst_n),
        
        // Lookup interface
        .lookup_arch_reg1(rat_lookup_rs1_1),
        .lookup_arch_reg2(rat_lookup_rs2_1),
        .lookup_arch_reg3(rat_lookup_rs1_2),
        .lookup_arch_reg4(rat_lookup_rs2_2),
        .lookup_enable1(rat_lookup_enable1),
        .lookup_enable2(rat_lookup_enable2),
        .lookup_enable3(rat_lookup_enable3),
        .lookup_enable4(rat_lookup_enable4),
        
        .phys_reg1(rat_phys_rs1_1),
        .phys_reg2(rat_phys_rs2_1),
        .phys_reg3(rat_phys_rs1_2),
        .phys_reg4(rat_phys_rs2_2),
        .valid1(rat_valid1),
        .valid2(rat_valid2),
        .valid3(rat_valid3),
        .valid4(rat_valid4),
        
        // Update interface
        .update_arch_reg1(rat_update_arch_reg1),
        .update_arch_reg2(rat_update_arch_reg2),
        .update_phys_reg1(rat_update_phys_reg1),
        .update_phys_reg2(rat_update_phys_reg2),
        .update_enable1(rat_update_enable1),
        .update_enable2(rat_update_enable2),
        
        // Commit interface
        .commit_arch_reg1(rat_commit_arch_reg1),
        .commit_arch_reg2(rat_commit_arch_reg2),
        .commit_phys_reg1(rat_commit_phys_reg1),
        .commit_phys_reg2(rat_commit_phys_reg2),
        .commit_enable1(rat_commit_enable1),
        .commit_enable2(rat_commit_enable2),
        
        // Flush interface (simplified)
        .flush_enable(flush_rename),
        .flush_arch_valid({`ARCH_REGS{1'b0}}),
        .flush_phys_regs_flat({(`ARCH_REGS*`PHYS_REG_BITS){1'b0}}),
        
        // Debug
        .debug_rat_table_flat()
    );
    
    rename_stage rename (
        .clk(clk),
        .rst_n(rst_n),
        
        // Input from decode
        .decode_pc1(decode_pc1),
        .decode_pc2(decode_pc2),
        .decode_instruction1(decode_instruction1),
        .decode_instruction2(decode_instruction2),
        .decode_rs1_1(decode_rs1_1),
        .decode_rs2_1(decode_rs2_1),
        .decode_rd_1(decode_rd_1),
        .decode_rs1_2(decode_rs1_2),
        .decode_rs2_2(decode_rs2_2),
        .decode_rd_2(decode_rd_2),
        .decode_immediate1(decode_immediate1),
        .decode_immediate2(decode_immediate2),
        .decode_inst_type1(decode_inst_type1),
        .decode_inst_type2(decode_inst_type2),
        .decode_exec_unit1(decode_exec_unit1),
        .decode_exec_unit2(decode_exec_unit2),
        .decode_alu_op1(decode_alu_op1),
        .decode_alu_op2(decode_alu_op2),
        .decode_branch_op1(decode_branch_op1),
        .decode_branch_op2(decode_branch_op2),
        .decode_mem_op1(decode_mem_op1),
        .decode_mem_op2(decode_mem_op2),
        .decode_valid1(decode_valid1),
        .decode_valid2(decode_valid2),
        
        // Output to reservation station
        .rename_pc1(rename_pc1),
        .rename_pc2(rename_pc2),
        .rename_instruction1(rename_instruction1),
        .rename_instruction2(rename_instruction2),
        .rename_phys_rs1_1(rename_phys_rs1_1),
        .rename_phys_rs2_1(rename_phys_rs2_1),
        .rename_phys_rd_1(rename_phys_rd_1),
        .rename_phys_rs1_2(rename_phys_rs1_2),
        .rename_phys_rs2_2(rename_phys_rs2_2),
        .rename_phys_rd_2(rename_phys_rd_2),
        .rename_arch_rd_1(rename_arch_rd_1),
        .rename_arch_rd_2(rename_arch_rd_2),
        .rename_immediate1(rename_immediate1),
        .rename_immediate2(rename_immediate2),
        .rename_inst_type1(rename_inst_type1),
        .rename_inst_type2(rename_inst_type2),
        .rename_exec_unit1(rename_exec_unit1),
        .rename_exec_unit2(rename_exec_unit2),
        .rename_alu_op1(rename_alu_op1),
        .rename_alu_op2(rename_alu_op2),
        .rename_branch_op1(rename_branch_op1),
        .rename_branch_op2(rename_branch_op2),
        .rename_mem_op1(rename_mem_op1),
        .rename_mem_op2(rename_mem_op2),
        .rename_rob_id1(rename_rob_id1),
        .rename_rob_id2(rename_rob_id2),
        .rename_valid1(rename_valid1),
        .rename_valid2(rename_valid2),
        
        // RAT interface
        .rat_lookup_rs1_1(rat_lookup_rs1_1),
        .rat_lookup_rs2_1(rat_lookup_rs2_1),
        .rat_lookup_rs1_2(rat_lookup_rs1_2),
        .rat_lookup_rs2_2(rat_lookup_rs2_2),
        .rat_lookup_enable1(rat_lookup_enable1),
        .rat_lookup_enable2(rat_lookup_enable2),
        .rat_lookup_enable3(rat_lookup_enable3),
        .rat_lookup_enable4(rat_lookup_enable4),
        .rat_phys_rs1_1(rat_phys_rs1_1),
        .rat_phys_rs2_1(rat_phys_rs2_1),
        .rat_phys_rs1_2(rat_phys_rs1_2),
        .rat_phys_rs2_2(rat_phys_rs2_2),
        .rat_valid1(rat_valid1),
        .rat_valid2(rat_valid2),
        .rat_valid3(rat_valid3),
        .rat_valid4(rat_valid4),
        
        .rat_update_arch_reg1(rat_update_arch_reg1),
        .rat_update_arch_reg2(rat_update_arch_reg2),
        .rat_update_phys_reg1(rat_update_phys_reg1),
        .rat_update_phys_reg2(rat_update_phys_reg2),
        .rat_update_enable1(rat_update_enable1),
        .rat_update_enable2(rat_update_enable2),
        
        // Free list interface
        .free_list_allocate_req1(free_list_allocate_req1),
        .free_list_allocate_req2(free_list_allocate_req2),
        .free_list_allocated_reg1(free_list_allocated_reg1),
        .free_list_allocated_reg2(free_list_allocated_reg2),
        .free_list_allocation_valid1(free_list_allocation_valid1),
        .free_list_allocation_valid2(free_list_allocation_valid2),
        
        // ROB interface
        .rob_allocate_req1(rob_allocate_req1),
        .rob_allocate_req2(rob_allocate_req2),
        .rob_allocated_id1(rob_allocated_id1),
        .rob_allocated_id2(rob_allocated_id2),
        .rob_allocation_valid1(rob_allocation_valid1),
        .rob_allocation_valid2(rob_allocation_valid2),
        
        // Pipeline control
        .stall_rename(stall_rename),
        .flush_rename(flush_rename),
        .rename_stall_req(rename_stall_req)
    );
    
    // =============================================================================
    // Reservation Station and Scheduler
    // =============================================================================
    
    instruction_scheduler scheduler (
        .clk(clk),
        .rst_n(rst_n),
        
        // Input from rename
        .rename_pc1(rename_pc1),
        .rename_pc2(rename_pc2),
        .rename_instruction1(rename_instruction1),
        .rename_instruction2(rename_instruction2),
        .rename_phys_rs1_1(rename_phys_rs1_1),
        .rename_phys_rs2_1(rename_phys_rs2_1),
        .rename_phys_rd_1(rename_phys_rd_1),
        .rename_phys_rs1_2(rename_phys_rs1_2),
        .rename_phys_rs2_2(rename_phys_rs2_2),
        .rename_phys_rd_2(rename_phys_rd_2),
        .rename_arch_rd_1(rename_arch_rd_1),
        .rename_arch_rd_2(rename_arch_rd_2),
        .rename_immediate1(rename_immediate1),
        .rename_immediate2(rename_immediate2),
        .rename_inst_type1(rename_inst_type1),
        .rename_inst_type2(rename_inst_type2),
        .rename_exec_unit1(rename_exec_unit1),
        .rename_exec_unit2(rename_exec_unit2),
        .rename_alu_op1(rename_alu_op1),
        .rename_alu_op2(rename_alu_op2),
        .rename_branch_op1(rename_branch_op1),
        .rename_branch_op2(rename_branch_op2),
        .rename_mem_op1(rename_mem_op1),
        .rename_mem_op2(rename_mem_op2),
        .rename_rob_id1(rename_rob_id1),
        .rename_rob_id2(rename_rob_id2),
        .rename_valid1(rename_valid1),
        .rename_valid2(rename_valid2),
        
        // Output to execution units
        .exec_pc1(exec_pc1),
        .exec_pc2(exec_pc2),
        .exec_instruction1(exec_instruction1),
        .exec_instruction2(exec_instruction2),
        .exec_operand1_1(exec_operand1_1),
        .exec_operand2_1(exec_operand2_1),
        .exec_operand1_2(exec_operand1_2),
        .exec_operand2_2(exec_operand2_2),
        .exec_phys_rd_1(exec_phys_rd_1),
        .exec_phys_rd_2(exec_phys_rd_2),
        .exec_arch_rd_1(exec_arch_rd_1),
        .exec_arch_rd_2(exec_arch_rd_2),
        .exec_immediate1(exec_immediate1),
        .exec_immediate2(exec_immediate2),
        .exec_inst_type1(exec_inst_type1),
        .exec_inst_type2(exec_inst_type2),
        .exec_exec_unit1(exec_exec_unit1),
        .exec_exec_unit2(exec_exec_unit2),
        .exec_alu_op1(exec_alu_op1),
        .exec_alu_op2(exec_alu_op2),
        .exec_branch_op1(exec_branch_op1),
        .exec_branch_op2(exec_branch_op2),
        .exec_mem_op1(exec_mem_op1),
        .exec_mem_op2(exec_mem_op2),
        .exec_rob_id1(exec_rob_id1),
        .exec_rob_id2(exec_rob_id2),
        .exec_valid1(exec_valid1),
        .exec_valid2(exec_valid2),
        
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
        
        .regfile_ready_addr1(regfile_ready_addr1),
        .regfile_ready_addr2(regfile_ready_addr2),
        .regfile_ready_out1(regfile_ready_out1),
        .regfile_ready_out2(regfile_ready_out2),
        
        // Wakeup interface
        .wakeup_tag1(wakeup_tag1),
        .wakeup_tag2(wakeup_tag2),
        .wakeup_valid1(wakeup_valid1),
        .wakeup_valid2(wakeup_valid2),
        
        // Pipeline control
        .stall_scheduler(stall_issue),
        .flush_scheduler(flush_issue),
        .scheduler_stall_req(scheduler_stall_req),
        
        // Flow control
        .exec_ready(1'b1),  // Simplified: always ready
        .rename_ready()
    );
    
    // =============================================================================
    // Execution Units
    // =============================================================================
    
    // Simple execution unit routing (simplified)
    wire exec_alu_valid1, exec_alu_valid2;
    wire exec_branch_valid1, exec_branch_valid2;
    wire exec_lsu_valid1, exec_lsu_valid2;
    
    assign exec_alu_valid1 = exec_valid1 && (exec_exec_unit1 == `EXEC_ALU);
    assign exec_alu_valid2 = exec_valid2 && (exec_exec_unit2 == `EXEC_ALU);
    assign exec_branch_valid1 = exec_valid1 && (exec_exec_unit1 == `EXEC_BRANCH);
    assign exec_branch_valid2 = exec_valid2 && (exec_exec_unit2 == `EXEC_BRANCH);
    assign exec_lsu_valid1 = exec_valid1 && (exec_exec_unit1 == `EXEC_LOAD_STORE);
    assign exec_lsu_valid2 = exec_valid2 && (exec_exec_unit2 == `EXEC_LOAD_STORE);
    
    alu_unit alu (
        .clk(clk),
        .rst_n(rst_n),
        
        // Input (simplified - using first instruction)
        .alu_pc(exec_pc1),
        .alu_instruction(exec_instruction1),
        .alu_operand1(exec_operand1_1),
        .alu_operand2(exec_operand2_1),
        .alu_immediate(exec_immediate1),
        .alu_phys_rd(exec_phys_rd_1),
        .alu_arch_rd(exec_arch_rd_1),
        .alu_op(exec_alu_op1),
        .alu_inst_type(exec_inst_type1),
        .alu_rob_id(exec_rob_id1),
        .alu_valid(exec_alu_valid1),
        
        // Output
        .alu_result_pc(alu_result_pc),
        .alu_result_instruction(alu_result_instruction),
        .alu_result(alu_result),
        .alu_result_phys_rd(alu_result_phys_rd),
        .alu_result_arch_rd(alu_result_arch_rd),
        .alu_result_rob_id(alu_result_rob_id),
        .alu_result_valid(alu_result_valid),
        .alu_exception(alu_exception),
        .alu_exception_code(alu_exception_code),
        
        // Bypass
        .alu_bypass_tag(wakeup_tag1),
        .alu_bypass_data(),
        .alu_bypass_valid(wakeup_valid1),
        
        // Pipeline control
        .stall_alu(stall_execute),
        .flush_alu(flush_execute)
    );
    
    branch_unit branch (
        .clk(clk),
        .rst_n(rst_n),
        
        // Input (simplified - using branch instruction)
        .branch_pc(exec_branch_valid1 ? exec_pc1 : exec_pc2),
        .branch_instruction(exec_branch_valid1 ? exec_instruction1 : exec_instruction2),
        .branch_operand1(exec_branch_valid1 ? exec_operand1_1 : exec_operand1_2),
        .branch_operand2(exec_branch_valid1 ? exec_operand2_1 : exec_operand2_2),
        .branch_immediate(exec_branch_valid1 ? exec_immediate1 : exec_immediate2),
        .branch_phys_rd(exec_branch_valid1 ? exec_phys_rd_1 : exec_phys_rd_2),
        .branch_arch_rd(exec_branch_valid1 ? exec_arch_rd_1 : exec_arch_rd_2),
        .branch_op(exec_branch_valid1 ? exec_branch_op1 : exec_branch_op2),
        .branch_rob_id(exec_branch_valid1 ? exec_rob_id1 : exec_rob_id2),
        .branch_predicted_taken(1'b0),  // Simplified
        .branch_predicted_target(32'b0),
        .branch_valid(exec_branch_valid1 || exec_branch_valid2),
        
        // Output
        .branch_result_pc(branch_result_pc),
        .branch_result_instruction(branch_result_instruction),
        .branch_result(branch_result),
        .branch_result_phys_rd(branch_result_phys_rd),
        .branch_result_arch_rd(branch_result_arch_rd),
        .branch_result_rob_id(branch_result_rob_id),
        .branch_result_valid(branch_result_valid),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .branch_mispredicted(branch_mispredicted),
        .branch_exception(branch_exception),
        .branch_exception_code(branch_exception_code),
        
        // Bypass
        .branch_bypass_tag(wakeup_tag2),
        .branch_bypass_data(),
        .branch_bypass_valid(wakeup_valid2),
        
        // Pipeline control
        .stall_branch(stall_execute),
        .flush_branch(flush_execute)
    );
    
    load_store_unit lsu (
        .clk(clk),
        .rst_n(rst_n),
        
        // Input (simplified - using LSU instruction)
        .lsu_pc(exec_lsu_valid1 ? exec_pc1 : exec_pc2),
        .lsu_instruction(exec_lsu_valid1 ? exec_instruction1 : exec_instruction2),
        .lsu_operand1(exec_lsu_valid1 ? exec_operand1_1 : exec_operand1_2),
        .lsu_operand2(exec_lsu_valid1 ? exec_operand2_1 : exec_operand2_2),
        .lsu_immediate(exec_lsu_valid1 ? exec_immediate1 : exec_immediate2),
        .lsu_phys_rd(exec_lsu_valid1 ? exec_phys_rd_1 : exec_phys_rd_2),
        .lsu_arch_rd(exec_lsu_valid1 ? exec_arch_rd_1 : exec_arch_rd_2),
        .lsu_mem_op(exec_lsu_valid1 ? exec_mem_op1 : exec_mem_op2),
        .lsu_rob_id(exec_lsu_valid1 ? exec_rob_id1 : exec_rob_id2),
        .lsu_is_load(decode_is_load1 || decode_is_load2),  // Simplified
        .lsu_is_store(decode_is_store1 || decode_is_store2),
        .lsu_valid(exec_lsu_valid1 || exec_lsu_valid2),
        
        // Memory interface
        .dcache_addr(dmem_addr),
        .dcache_wdata(dmem_wdata),
        .dcache_be(dmem_be),
        .dcache_we(dmem_we),
        .dcache_req(dmem_req),
        .dcache_ready(dmem_ready),
        .dcache_valid(dmem_valid),
        .dcache_rdata(dmem_rdata),
        .dcache_error(1'b0),
        
        // Output
        .lsu_result_pc(lsu_result_pc),
        .lsu_result_instruction(lsu_result_instruction),
        .lsu_result(lsu_result),
        .lsu_result_phys_rd(lsu_result_phys_rd),
        .lsu_result_arch_rd(lsu_result_arch_rd),
        .lsu_result_rob_id(lsu_result_rob_id),
        .lsu_result_valid(lsu_result_valid),
        .lsu_exception(lsu_exception),
        .lsu_exception_code(lsu_exception_code),
        
        // Bypass
        .lsu_bypass_tag(),
        .lsu_bypass_data(),
        .lsu_bypass_valid(),
        
        // Pipeline control
        .stall_lsu(stall_execute),
        .flush_lsu(flush_execute)
    );
    
    // =============================================================================
    // ROB and Commit Stage
    // =============================================================================
    
    rob_controller rob (
        .clk(clk),
        .rst_n(rst_n),
        
        // Allocation interface
        .allocate_req1(rob_allocate_req1),
        .allocate_req2(rob_allocate_req2),
        .alloc_pc1(rename_pc1),
        .alloc_pc2(rename_pc2),
        .alloc_arch_reg1(rename_arch_rd_1),
        .alloc_arch_reg2(rename_arch_rd_2),
        .alloc_phys_reg1(rename_phys_rd_1),
        .alloc_phys_reg2(rename_phys_rd_2),
        .alloc_instruction1(rename_instruction1),
        .alloc_instruction2(rename_instruction2),
        .alloc_exec_unit1(rename_exec_unit1),
        .alloc_exec_unit2(rename_exec_unit2),
        .alloc_is_branch1(decode_is_branch1),
        .alloc_is_branch2(decode_is_branch2),
        .alloc_is_store1(decode_is_store1),
        .alloc_is_store2(decode_is_store2),
        
        .allocated_rob_id1(rob_allocated_id1),
        .allocated_rob_id2(rob_allocated_id2),
        .allocation_valid1(rob_allocation_valid1),
        .allocation_valid2(rob_allocation_valid2),
        
        // Completion interface (simplified - ALU only)
        .complete_rob_id1(alu_result_rob_id),
        .complete_rob_id2(branch_result_rob_id),
        .complete_result1(alu_result),
        .complete_result2(branch_result),
        .complete_valid1(alu_result_valid),
        .complete_valid2(branch_result_valid),
        .complete_exception1(alu_exception),
        .complete_exception2(branch_exception),
        .complete_exception_code1(alu_exception_code),
        .complete_exception_code2(branch_exception_code),
        .complete_branch_taken1(1'b0),
        .complete_branch_taken2(branch_taken),
        .complete_branch_target1(32'b0),
        .complete_branch_target2(branch_target),
        .complete_branch_mispredicted1(1'b0),
        .complete_branch_mispredicted2(branch_mispredicted),
        
        // Commit interface
        .commit_rob_id1(commit_rob_id1),
        .commit_rob_id2(commit_rob_id2),
        .commit_pc1(commit_pc1),
        .commit_pc2(commit_pc2),
        .commit_arch_reg1(commit_arch_reg1),
        .commit_arch_reg2(commit_arch_reg2),
        .commit_phys_reg1(commit_phys_reg1),
        .commit_phys_reg2(commit_phys_reg2),
        .commit_result1(commit_result1),
        .commit_result2(commit_result2),
        .commit_instruction1(commit_instruction1),
        .commit_instruction2(commit_instruction2),
        .commit_valid1(commit_valid1),
        .commit_valid2(commit_valid2),
        .commit_exception1(commit_exception1),
        .commit_exception2(commit_exception2),
        .commit_exception_code1(commit_exception_code1),
        .commit_exception_code2(commit_exception_code2),
        .commit_is_branch1(commit_is_branch1),
        .commit_is_branch2(commit_is_branch2),
        .commit_branch_taken1(commit_branch_taken1),
        .commit_branch_taken2(commit_branch_taken2),
        .commit_branch_target1(commit_branch_target1),
        .commit_branch_target2(commit_branch_target2),
        .commit_branch_mispredicted1(commit_branch_mispredicted1),
        .commit_branch_mispredicted2(commit_branch_mispredicted2),
        .commit_is_store1(commit_is_store1),
        .commit_is_store2(commit_is_store2),
        
        // Flush interface
        .flush_enable(flush_execute),
        .flush_rob_id({`ROB_ADDR_BITS{1'b0}}),
        
        // Status
        .rob_entries_used(rob_entries_used),
        .rob_full(rob_full),
        .rob_empty(rob_empty),
        
        // Debug
        .debug_head_ptr(),
        .debug_tail_ptr()
    );
    
    commit_stage commit (
        .clk(clk),
        .rst_n(rst_n),
        
        // Input from ROB
        .rob_commit_id1(commit_rob_id1),
        .rob_commit_id2(commit_rob_id2),
        .rob_commit_pc1(commit_pc1),
        .rob_commit_pc2(commit_pc2),
        .rob_commit_arch_reg1(commit_arch_reg1),
        .rob_commit_arch_reg2(commit_arch_reg2),
        .rob_commit_phys_reg1(commit_phys_reg1),
        .rob_commit_phys_reg2(commit_phys_reg2),
        .rob_commit_result1(commit_result1),
        .rob_commit_result2(commit_result2),
        .rob_commit_instruction1(commit_instruction1),
        .rob_commit_instruction2(commit_instruction2),
        .rob_commit_valid1(commit_valid1),
        .rob_commit_valid2(commit_valid2),
        .rob_commit_exception1(commit_exception1),
        .rob_commit_exception2(commit_exception2),
        .rob_commit_exception_code1(commit_exception_code1),
        .rob_commit_exception_code2(commit_exception_code2),
        .rob_commit_is_branch1(commit_is_branch1),
        .rob_commit_is_branch2(commit_is_branch2),
        .rob_commit_branch_taken1(commit_branch_taken1),
        .rob_commit_branch_taken2(commit_branch_taken2),
        .rob_commit_branch_target1(commit_branch_target1),
        .rob_commit_branch_target2(commit_branch_target2),
        .rob_commit_branch_mispredicted1(commit_branch_mispredicted1),
        .rob_commit_branch_mispredicted2(commit_branch_mispredicted2),
        .rob_commit_is_store1(commit_is_store1),
        .rob_commit_is_store2(commit_is_store2),
        
        // Register file writeback
        .regfile_write_addr1(regfile_write_addr1),
        .regfile_write_addr2(regfile_write_addr2),
        .regfile_write_data1(regfile_write_data1),
        .regfile_write_data2(regfile_write_data2),
        .regfile_write_enable1(regfile_write_enable1),
        .regfile_write_enable2(regfile_write_enable2),
        
        // RAT update
        .rat_commit_arch_reg1(rat_commit_arch_reg1),
        .rat_commit_arch_reg2(rat_commit_arch_reg2),
        .rat_commit_phys_reg1(rat_commit_phys_reg1),
        .rat_commit_phys_reg2(rat_commit_phys_reg2),
        .rat_commit_enable1(rat_commit_enable1),
        .rat_commit_enable2(rat_commit_enable2),
        
        // Free list (simplified)
        .free_list_return_reg1(),
        .free_list_return_reg2(),
        .free_list_return_enable1(),
        .free_list_return_enable2(),
        
        // Branch prediction update
        .bp_update_pc1(bp_update_pc1),
        .bp_update_pc2(bp_update_pc2),
        .bp_update_taken1(bp_update_taken1),
        .bp_update_taken2(bp_update_taken2),
        .bp_update_target1(bp_update_target1),
        .bp_update_target2(bp_update_target2),
        .bp_update_valid1(bp_update_valid1),
        .bp_update_valid2(bp_update_valid2),
        
        // Exception handling
        .exception_occurred(exception_occurred),
        .exception_code(exception_code),
        .exception_pc(exception_pc),
        .exception_instruction(),
        
        // Branch misprediction
        .branch_misprediction(branch_misprediction),
        .branch_correct_target(branch_correct_target),
        .branch_rob_id(),
        
        // Store commit
        .store_commit_pc1(),
        .store_commit_pc2(),
        .store_commit_valid1(),
        .store_commit_valid2(),
        
        // Performance counters
        .committed_instructions(committed_instructions),
        .committed_branches(),
        .committed_stores(),
        .branch_mispredictions()
    );
    
    // =============================================================================
    // Performance Monitoring and Debug
    // =============================================================================
    
    reg [31:0] cycle_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_counter <= 32'b0;
        end
        else begin
            cycle_counter <= cycle_counter + 1;
        end
    end
    
    assign total_cycles = cycle_counter;
    assign processor_idle = rob_empty && rs_empty && fetch_queue_empty;
    assign debug_instruction = commit_instruction1;
    assign debug_instruction_valid = commit_valid1;

endmodule
