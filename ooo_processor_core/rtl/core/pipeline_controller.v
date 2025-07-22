// =============================================================================
// Pipeline Controller
// =============================================================================
// File: pipeline_controller.v
// Description: Pipeline control, hazard detection, and stall/flush management
// Author: Suryaa Senthilkumar Shanthi
// Date: 16 July 2025
// =============================================================================

`include "ooo_processor_defines.vh"

// =============================================================================
// Hazard Detection Unit
// =============================================================================
// Detects various types of hazards and generates stall/flush signals

module hazard_detection (
    input wire clk,
    input wire rst_n,
    
    // Status inputs from pipeline stages
    input wire fetch_queue_full,
    input wire fetch_queue_empty,
    input wire decode_stall_req,
    input wire rename_stall_req,
    input wire rs_full,
    input wire rs_empty,
    input wire rob_full,
    input wire rob_empty,
    input wire free_list_empty,
    input wire [`RS_ADDR_BITS:0] rs_entries_used,
    input wire [`ROB_ADDR_BITS:0] rob_entries_used,
    
    // Execution unit status
    input wire alu_busy,
    input wire branch_busy,
    input wire lsu_busy,
    input wire dcache_miss,
    input wire icache_miss,
    
    // Exception and branch misprediction inputs
    input wire exception_occurred,
    input wire branch_misprediction,
    input wire [`XLEN-1:0] exception_pc,
    input wire [`XLEN-1:0] branch_target_pc,
    
    // Output stall signals
    output reg stall_fetch,
    output reg stall_decode,
    output reg stall_rename,
    output reg stall_issue,
    output reg stall_execute,
    
    // Output flush signals
    output reg flush_fetch,
    output reg flush_decode,
    output reg flush_rename,
    output reg flush_issue,
    output reg flush_execute,
    
    // Recovery control
    output reg recovery_mode,
    output reg [`XLEN-1:0] recovery_pc,
    
    // Performance monitoring
    output reg [31:0] stall_cycles,
    output reg [31:0] flush_cycles,
    output reg [31:0] hazard_count
);

    // =============================================================================
    // Hazard Detection Logic
    // =============================================================================
    
    // Resource hazards
    wire structural_hazard;
    wire resource_hazard;
    wire memory_hazard;
    
    // Control hazards
    wire control_hazard;
    wire exception_hazard;
    
    // Detect structural hazards (resource conflicts)
    assign structural_hazard = rs_full || rob_full || free_list_empty;
    
    // Detect resource hazards (execution units busy)
    assign resource_hazard = (alu_busy && rs_entries_used > 0) ||
                            (branch_busy && rs_entries_used > 0) ||
                            (lsu_busy && rs_entries_used > 0);
    
    // Detect memory hazards (cache misses)
    assign memory_hazard = icache_miss || dcache_miss;
    
    // Detect control hazards
    assign control_hazard = branch_misprediction;
    assign exception_hazard = exception_occurred;
    
    // =============================================================================
    // Stall Logic Priority (Higher priority = more urgent)
    // =============================================================================
    // Priority: Exception > Branch Misprediction > Structural > Resource > Memory
    
    always @(*) begin
        // Default: no stalls
        stall_fetch = 1'b0;
        stall_decode = 1'b0;
        stall_rename = 1'b0;
        stall_issue = 1'b0;
        stall_execute = 1'b0;
        
        // Exception handling (highest priority)
        if (exception_hazard) begin
            stall_fetch = 1'b1;
            stall_decode = 1'b1;
            stall_rename = 1'b1;
            stall_issue = 1'b1;
            stall_execute = 1'b0;  // Let current execute complete
        end
        // Branch misprediction (second priority)
        else if (control_hazard) begin
            stall_fetch = 1'b1;
            stall_decode = 1'b1;
            stall_rename = 1'b1;
            stall_issue = 1'b1;
            stall_execute = 1'b0;  // Let current execute complete
        end
        // Structural hazards (third priority)
        else if (structural_hazard) begin
            stall_fetch = rob_full || fetch_queue_full;
            stall_decode = rob_full || rs_full;
            stall_rename = rob_full || rs_full || free_list_empty;
            stall_issue = rs_full;
            stall_execute = 1'b0;
        end
        // Resource hazards (fourth priority)
        else if (resource_hazard) begin
            stall_fetch = 1'b0;
            stall_decode = 1'b0;
            stall_rename = 1'b0;
            stall_issue = 1'b1;  // Can't issue if execution units busy
            stall_execute = 1'b0;
        end
        // Memory hazards (lowest priority)
        else if (memory_hazard) begin
            stall_fetch = icache_miss;
            stall_decode = 1'b0;
            stall_rename = 1'b0;
            stall_issue = 1'b0;
            stall_execute = dcache_miss;
        end
        
        // Additional stalls from individual stages
        if (decode_stall_req) stall_decode = 1'b1;
        if (rename_stall_req) stall_rename = 1'b1;
    end
    
    // =============================================================================
    // Flush Logic
    // =============================================================================
    
    always @(*) begin
        // Default: no flushes
        flush_fetch = 1'b0;
        flush_decode = 1'b0;
        flush_rename = 1'b0;
        flush_issue = 1'b0;
        flush_execute = 1'b0;
        
        // Exception flush (flush entire pipeline)
        if (exception_hazard) begin
            flush_fetch = 1'b1;
            flush_decode = 1'b1;
            flush_rename = 1'b1;
            flush_issue = 1'b1;
            flush_execute = 1'b1;
        end
        // Branch misprediction flush (flush frontend)
        else if (control_hazard) begin
            flush_fetch = 1'b1;
            flush_decode = 1'b1;
            flush_rename = 1'b1;
            flush_issue = 1'b1;
            flush_execute = 1'b0;  // Backend instructions may be correct
        end
    end
    
    // =============================================================================
    // Recovery Control
    // =============================================================================
    
    always @(*) begin
        recovery_mode = exception_hazard || control_hazard;
        
        if (exception_hazard) begin
            recovery_pc = exception_pc;
        end
        else if (control_hazard) begin
            recovery_pc = branch_target_pc;
        end
        else begin
            recovery_pc = {`XLEN{1'b0}};
        end
    end
    
    // =============================================================================
    // Performance Monitoring
    // =============================================================================
    
    reg any_stall, any_flush;
    
    always @(*) begin
        any_stall = stall_fetch || stall_decode || stall_rename || stall_issue || stall_execute;
        any_flush = flush_fetch || flush_decode || flush_rename || flush_issue || flush_execute;
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stall_cycles <= 32'b0;
            flush_cycles <= 32'b0;
            hazard_count <= 32'b0;
        end
        else begin
            if (any_stall) begin
                stall_cycles <= stall_cycles + 1;
            end
            
            if (any_flush) begin
                flush_cycles <= flush_cycles + 1;
            end
            
            if (structural_hazard || resource_hazard || memory_hazard || 
                control_hazard || exception_hazard) begin
                hazard_count <= hazard_count + 1;
            end
        end
    end

endmodule

// =============================================================================
// Pipeline Flush Controller
// =============================================================================
// Manages selective flushing and recovery operations

module pipeline_flush (
    input wire clk,
    input wire rst_n,
    
    // Flush triggers
    input wire branch_misprediction,
    input wire exception_occurred,
    input wire [`XLEN-1:0] recovery_pc,
    input wire [`ROB_ADDR_BITS-1:0] branch_rob_id,
    
    // ROB interface for selective flush
    output reg rob_flush_enable,
    output reg [`ROB_ADDR_BITS-1:0] rob_flush_id,
    
    // RAT interface for recovery
    output reg rat_flush_enable,
    output reg [`ARCH_REGS-1:0] rat_flush_arch_valid,
    output reg [`ARCH_REGS*`PHYS_REG_BITS-1:0] rat_flush_phys_regs_flat,
    
    // RS interface for flush
    output reg rs_flush_enable,
    
    // Global flush control
    output reg global_flush_active,
    output reg [`XLEN-1:0] flush_target_pc,
    
    // Flush completion status
    output reg flush_complete
);

    // =============================================================================
    // Flush State Machine
    // =============================================================================
    
    localparam FLUSH_IDLE       = 3'b000;
    localparam FLUSH_ROB        = 3'b001;
    localparam FLUSH_RAT        = 3'b010;
    localparam FLUSH_RS         = 3'b011;
    localparam FLUSH_COMPLETE   = 3'b100;
    
    reg [2:0] flush_state, next_flush_state;
    reg flush_request;
    reg [2:0] flush_counter;
    
    // Detect flush request
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flush_request <= 1'b0;
        end
        else begin
            flush_request <= branch_misprediction || exception_occurred;
        end
    end
    
    // Flush state machine
    always @(*) begin
        case (flush_state)
            FLUSH_IDLE: begin
                if (flush_request) begin
                    next_flush_state = FLUSH_ROB;
                end
                else begin
                    next_flush_state = FLUSH_IDLE;
                end
            end
            
            FLUSH_ROB: begin
                next_flush_state = FLUSH_RAT;
            end
            
            FLUSH_RAT: begin
                next_flush_state = FLUSH_RS;
            end
            
            FLUSH_RS: begin
                next_flush_state = FLUSH_COMPLETE;
            end
            
            FLUSH_COMPLETE: begin
                if (flush_counter == 3'b111) begin  // Hold for a few cycles
                    next_flush_state = FLUSH_IDLE;
                end
                else begin
                    next_flush_state = FLUSH_COMPLETE;
                end
            end
            
            default: next_flush_state = FLUSH_IDLE;
        endcase
    end
    
    // =============================================================================
    // Flush Control Outputs
    // =============================================================================
    
    always @(*) begin
        // Default outputs
        rob_flush_enable = 1'b0;
        rob_flush_id = {`ROB_ADDR_BITS{1'b0}};
        rat_flush_enable = 1'b0;
        rat_flush_arch_valid = {`ARCH_REGS{1'b0}};
        rat_flush_phys_regs_flat = {(`ARCH_REGS*`PHYS_REG_BITS){1'b0}};
        rs_flush_enable = 1'b0;
        global_flush_active = 1'b0;
        flush_target_pc = recovery_pc;
        flush_complete = 1'b0;
        
        case (flush_state)
            FLUSH_ROB: begin
                rob_flush_enable = 1'b1;
                rob_flush_id = branch_rob_id;
                global_flush_active = 1'b1;
            end
            
            FLUSH_RAT: begin
                rat_flush_enable = 1'b1;
                // Simplified: flush all architectural registers
                rat_flush_arch_valid = {`ARCH_REGS{1'b1}};
                global_flush_active = 1'b1;
            end
            
            FLUSH_RS: begin
                rs_flush_enable = 1'b1;
                global_flush_active = 1'b1;
            end
            
            FLUSH_COMPLETE: begin
                flush_complete = 1'b1;
            end
            
            default: begin
                // All outputs already set to defaults
            end
        endcase
    end
    
    // =============================================================================
    // Sequential Logic
    // =============================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flush_state <= FLUSH_IDLE;
            flush_counter <= 3'b0;
        end
        else begin
            flush_state <= next_flush_state;
            
            if (flush_state == FLUSH_COMPLETE) begin
                flush_counter <= flush_counter + 1;
            end
            else begin
                flush_counter <= 3'b0;
            end
        end
    end

endmodule

// =============================================================================
// Stall Controller
// =============================================================================
// Manages pipeline stalls and backpressure

module stall_controller (
    input wire clk,
    input wire rst_n,
    
    // Resource status inputs
    input wire [`RS_ADDR_BITS:0] rs_entries_used,
    input wire [`ROB_ADDR_BITS:0] rob_entries_used,
    input wire [`PHYS_REG_BITS:0] free_regs_available,
    input wire fetch_queue_entries,
    
    // Execution unit status
    input wire alu_available,
    input wire branch_available, 
    input wire lsu_available,
    
    // Memory system status
    input wire icache_ready,
    input wire dcache_ready,
    
    // Individual stage stall requests
    input wire fetch_stall_req,
    input wire decode_stall_req,
    input wire rename_stall_req,
    input wire issue_stall_req,
    
    // Output stall enables
    output reg enable_fetch,
    output reg enable_decode,
    output reg enable_rename,
    output reg enable_issue,
    output reg enable_execute,
    
    // Backpressure signals
    output reg backpressure_active,
    output reg [`XLEN-1:0] stall_reason,
    
    // Performance counters
    output reg [31:0] total_stall_cycles,
    output reg [31:0] resource_stall_cycles,
    output reg [31:0] memory_stall_cycles
);

    // =============================================================================
    // Resource Availability Checks
    // =============================================================================
    
    wire rs_available, rob_available, regs_available;
    wire fetch_buffer_available, memory_available;
    wire execution_available;
    
    // Check if resources are available for new allocations
    assign rs_available = (rs_entries_used < (`RS_SIZE - 2));  // Keep 2 slots free
    assign rob_available = (rob_entries_used < (`ROB_SIZE - 2));
    assign regs_available = (free_regs_available > 2);
    assign fetch_buffer_available = (fetch_queue_entries < (`FETCH_QUEUE_SIZE - 2));
    assign memory_available = icache_ready && dcache_ready;
    assign execution_available = alu_available && branch_available && lsu_available;
    
    // =============================================================================
    // Stall Decision Logic
    // =============================================================================
    
    reg resource_stall, memory_stall, structural_stall;
    
    always @(*) begin
        // Resource-based stalls
        resource_stall = !rs_available || !rob_available || !regs_available;
        
        // Memory-based stalls
        memory_stall = !memory_available;
        
        // Structural stalls (execution units busy)
        structural_stall = !execution_available;
        
        // Enable signals (active high)
        enable_fetch = fetch_buffer_available && memory_available && 
                      !fetch_stall_req && !resource_stall;
        
        enable_decode = !decode_stall_req && !resource_stall;
        
        enable_rename = rs_available && rob_available && regs_available && 
                       !rename_stall_req;
        
        enable_issue = execution_available && !issue_stall_req && !structural_stall;
        
        enable_execute = memory_available && !memory_stall;
        
        // Backpressure detection
        backpressure_active = resource_stall || memory_stall || structural_stall;
        
        // Stall reason encoding
        if (resource_stall) begin
            stall_reason = 32'h00000001;  // Resource stall
        end
        else if (memory_stall) begin
            stall_reason = 32'h00000002;  // Memory stall
        end
        else if (structural_stall) begin
            stall_reason = 32'h00000003;  // Structural stall
        end
        else begin
            stall_reason = 32'h00000000;  // No stall
        end
    end
    
    // =============================================================================
    // Performance Monitoring
    // =============================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_stall_cycles <= 32'b0;
            resource_stall_cycles <= 32'b0;
            memory_stall_cycles <= 32'b0;
        end
        else begin
            if (backpressure_active) begin
                total_stall_cycles <= total_stall_cycles + 1;
            end
            
            if (resource_stall) begin
                resource_stall_cycles <= resource_stall_cycles + 1;
            end
            
            if (memory_stall) begin
                memory_stall_cycles <= memory_stall_cycles + 1;
            end
        end
    end

endmodule
