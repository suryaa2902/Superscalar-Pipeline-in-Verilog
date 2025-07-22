// =============================================================================
// Instruction Fetch Unit
// =============================================================================
// File: fetch_unit.v
// Description: Instruction fetch, branch prediction, and fetch queue
// Author: Suryaa Senthilkumar Shanthi
// Date: 13 July 2025
// =============================================================================

`include "ooo_processor_defines.vh"

// =============================================================================
// Instruction Fetch Unit
// =============================================================================
// Manages PC, fetches instructions from I-cache, handles branch prediction

module instruction_fetch (
    input wire clk,
    input wire rst_n,
    
    // Memory interface (to I-cache)
    output wire [`XLEN-1:0] icache_addr,
    output wire icache_req,
    input wire icache_ready,
    input wire icache_valid,
    input wire [63:0] icache_data,       // 64-bit fetch (2 instructions)
    input wire icache_error,
    
    // Branch prediction interface
    output wire [`XLEN-1:0] bp_fetch_pc,
    output wire bp_fetch_req,
    input wire bp_prediction,
    input wire [`XLEN-1:0] bp_target,
    input wire bp_valid,
    
    // Branch resolution interface (from commit stage)
    input wire [`XLEN-1:0] bp_update_pc,
    input wire bp_update_taken,
    input wire [`XLEN-1:0] bp_update_target,
    input wire bp_update_valid,
    
    // Branch misprediction recovery
    input wire branch_misprediction,
    input wire [`XLEN-1:0] branch_correct_pc,
    
    // Exception/interrupt handling
    input wire exception_occurred,
    input wire [`XLEN-1:0] exception_vector,
    
    // Output to fetch queue
    output reg [`XLEN-1:0] fetch_pc1,
    output reg [`XLEN-1:0] fetch_pc2,
    output reg [31:0] fetch_instruction1,
    output reg [31:0] fetch_instruction2,
    output reg fetch_valid1,
    output reg fetch_valid2,
    output reg fetch_predicted_taken1,
    output reg fetch_predicted_taken2,
    output reg [`XLEN-1:0] fetch_predicted_target1,
    output reg [`XLEN-1:0] fetch_predicted_target2,
    
    // Pipeline control
    input wire stall_fetch,
    input wire flush_fetch,
    output wire fetch_stall_req,
    
    // Debug interface
    output wire [`XLEN-1:0] debug_current_pc,
    output wire debug_fetch_busy
);

    // =============================================================================
    // Program Counter Management
    // =============================================================================
    
    reg [`XLEN-1:0] pc;
    reg [`XLEN-1:0] next_pc;
    reg fetch_busy;
    reg fetch_request_pending;
    
    // PC calculation logic
    always @(*) begin
        if (exception_occurred) begin
            next_pc = exception_vector;
        end
        else if (branch_misprediction) begin
            next_pc = branch_correct_pc;
        end
        else if (bp_valid && bp_prediction) begin
            next_pc = bp_target;
        end
        else begin
            next_pc = pc + 8;  // Fetch 2 instructions (8 bytes) per cycle
        end
    end
    
    // =============================================================================
    // Fetch State Machine
    // =============================================================================
    
    localparam FETCH_IDLE = 2'b00;
    localparam FETCH_REQ  = 2'b01;
    localparam FETCH_WAIT = 2'b10;
    
    reg [1:0] fetch_state;
    reg [1:0] next_fetch_state;
    
    always @(*) begin
        case (fetch_state)
            FETCH_IDLE: begin
                if (!stall_fetch && !flush_fetch) begin
                    next_fetch_state = FETCH_REQ;
                end else begin
                    next_fetch_state = FETCH_IDLE;
                end
            end
            
            FETCH_REQ: begin
                if (icache_ready) begin
                    next_fetch_state = FETCH_WAIT;
                end else begin
                    next_fetch_state = FETCH_REQ;
                end
            end
            
            FETCH_WAIT: begin
                if (icache_valid) begin
                    if (stall_fetch) begin
                        next_fetch_state = FETCH_IDLE;
                    end else begin
                        next_fetch_state = FETCH_REQ;
                    end
                end else if (icache_error) begin
                    next_fetch_state = FETCH_IDLE;
                end else begin
                    next_fetch_state = FETCH_WAIT;
                end
            end
            
            default: next_fetch_state = FETCH_IDLE;
        endcase
    end
    
    // =============================================================================
    // Fetch Control Logic
    // =============================================================================
    
    assign icache_addr = pc;
    assign icache_req = (fetch_state == FETCH_REQ);
    assign bp_fetch_pc = pc;
    assign bp_fetch_req = (fetch_state == FETCH_REQ);
    assign fetch_stall_req = (fetch_state == FETCH_REQ) && !icache_ready;
    
    // =============================================================================
    // Instruction Processing
    // =============================================================================
    
    wire [31:0] instruction1, instruction2;
    wire [`XLEN-1:0] pc1, pc2;
    wire is_branch1, is_branch2;
    wire branch_prediction1, branch_prediction2;
    wire [`XLEN-1:0] branch_target1, branch_target2;
    
    // Extract instructions from 64-bit cache line
    assign instruction1 = icache_data[31:0];
    assign instruction2 = icache_data[63:32];
    assign pc1 = pc;
    assign pc2 = pc + 4;
    
    // Simple branch detection (can be enhanced)
    assign is_branch1 = (instruction1[6:0] == `OPCODE_BRANCH) || 
                       (instruction1[6:0] == `OPCODE_JAL) || 
                       (instruction1[6:0] == `OPCODE_JALR);
    assign is_branch2 = (instruction2[6:0] == `OPCODE_BRANCH) || 
                       (instruction2[6:0] == `OPCODE_JAL) || 
                       (instruction2[6:0] == `OPCODE_JALR);
    
    // Branch prediction for each instruction
    assign branch_prediction1 = is_branch1 && bp_prediction;
    assign branch_prediction2 = is_branch2 && bp_prediction;
    assign branch_target1 = bp_target;
    assign branch_target2 = bp_target;
    
    // =============================================================================
    // Sequential Logic
    // =============================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h00000000;  // Reset vector
            fetch_state <= FETCH_IDLE;
            fetch_busy <= 1'b0;
            fetch_request_pending <= 1'b0;
            
            fetch_pc1 <= {`XLEN{1'b0}};
            fetch_pc2 <= {`XLEN{1'b0}};
            fetch_instruction1 <= 32'b0;
            fetch_instruction2 <= 32'b0;
            fetch_valid1 <= 1'b0;
            fetch_valid2 <= 1'b0;
            fetch_predicted_taken1 <= 1'b0;
            fetch_predicted_taken2 <= 1'b0;
            fetch_predicted_target1 <= {`XLEN{1'b0}};
            fetch_predicted_target2 <= {`XLEN{1'b0}};
        end
        else begin
            fetch_state <= next_fetch_state;
            
            // Handle PC updates
            if (exception_occurred || branch_misprediction || flush_fetch) begin
                pc <= next_pc;
                fetch_valid1 <= 1'b0;
                fetch_valid2 <= 1'b0;
            end
            else if (icache_valid && (fetch_state == FETCH_WAIT) && !stall_fetch) begin
                pc <= next_pc;
                
                // Update fetch outputs
                fetch_pc1 <= pc1;
                fetch_pc2 <= pc2;
                fetch_instruction1 <= instruction1;
                fetch_instruction2 <= instruction2;
                fetch_valid1 <= 1'b1;
                fetch_valid2 <= 1'b1;
                fetch_predicted_taken1 <= branch_prediction1;
                fetch_predicted_taken2 <= branch_prediction2;
                fetch_predicted_target1 <= branch_target1;
                fetch_predicted_target2 <= branch_target2;
            end
            else if (stall_fetch) begin
                // Maintain current outputs when stalled
                fetch_valid1 <= fetch_valid1;
                fetch_valid2 <= fetch_valid2;
            end
        end
    end
    
    // =============================================================================
    // Debug Interface
    // =============================================================================
    
    assign debug_current_pc = pc;
    assign debug_fetch_busy = (fetch_state != FETCH_IDLE);

endmodule

// =============================================================================
// Branch Predictor
// =============================================================================
// 2-bit saturating counter branch predictor with BTB

module branch_predictor (
    input wire clk,
    input wire rst_n,
    
    // Prediction interface
    input wire [`XLEN-1:0] fetch_pc,
    input wire prediction_req,
    output wire prediction,
    output wire [`XLEN-1:0] predicted_target,
    output wire prediction_valid,
    
    // Update interface (from commit stage)
    input wire [`XLEN-1:0] update_pc,
    input wire update_taken,
    input wire [`XLEN-1:0] update_target,
    input wire update_valid,
    
    // Debug interface
    output wire [`XLEN-1:0] debug_predictions,
    output wire [`XLEN-1:0] debug_mispredictions
);

    // =============================================================================
    // Branch History Table (BHT) - 2-bit saturating counters
    // =============================================================================
    
    localparam BHT_ADDR_BITS = $clog2(`BHT_SIZE);
    
    reg [1:0] bht [`BHT_SIZE-1:0];
    wire [BHT_ADDR_BITS-1:0] bht_index;
    wire [BHT_ADDR_BITS-1:0] bht_update_index;
    
    assign bht_index = fetch_pc[BHT_ADDR_BITS+1:2];  // Use PC bits, skip lower 2
    assign bht_update_index = update_pc[BHT_ADDR_BITS+1:2];
    
    // =============================================================================
    // Branch Target Buffer (BTB)
    // =============================================================================
    
    localparam BTB_ADDR_BITS = $clog2(`BTB_SIZE);
    
    reg [`XLEN-1:0] btb_targets [`BTB_SIZE-1:0];
    reg [`XLEN-1:0] btb_tags [`BTB_SIZE-1:0];
    reg [`BTB_SIZE-1:0] btb_valid;
    
    wire [BTB_ADDR_BITS-1:0] btb_index;
    wire [BTB_ADDR_BITS-1:0] btb_update_index;
    wire [`XLEN-1:0] btb_tag;
    wire [`XLEN-1:0] btb_update_tag;
    wire btb_hit;
    
    assign btb_index = fetch_pc[BTB_ADDR_BITS+1:2];
    assign btb_update_index = update_pc[BTB_ADDR_BITS+1:2];
    assign btb_tag = fetch_pc[`XLEN-1:BTB_ADDR_BITS+2];
    assign btb_update_tag = update_pc[`XLEN-1:BTB_ADDR_BITS+2];
    
    assign btb_hit = btb_valid[btb_index] && (btb_tags[btb_index] == btb_tag);
    
    // =============================================================================
    // Prediction Logic
    // =============================================================================
    
    wire bht_prediction;
    
    assign bht_prediction = bht[bht_index][1];  // MSB of 2-bit counter
    assign prediction = prediction_req && bht_prediction && btb_hit;
    assign predicted_target = btb_targets[btb_index];
    assign prediction_valid = prediction_req;
    
    // =============================================================================
    // Performance Counters
    // =============================================================================
    
    reg [`XLEN-1:0] total_predictions;
    reg [`XLEN-1:0] total_mispredictions;
    
    assign debug_predictions = total_predictions;
    assign debug_mispredictions = total_mispredictions;
    
    // =============================================================================
    // Sequential Logic
    // =============================================================================
    
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize BHT to weakly not taken (2'b01)
            for (i = 0; i < `BHT_SIZE; i = i + 1) begin
                bht[i] <= 2'b01;
            end
            
            // Initialize BTB
            for (i = 0; i < `BTB_SIZE; i = i + 1) begin
                btb_targets[i] <= {`XLEN{1'b0}};
                btb_tags[i] <= {`XLEN{1'b0}};
            end
            btb_valid <= {`BTB_SIZE{1'b0}};
            
            // Initialize performance counters
            total_predictions <= {`XLEN{1'b0}};
            total_mispredictions <= {`XLEN{1'b0}};
        end
        else begin
            // Handle prediction updates
            if (update_valid) begin
                // Update BHT with 2-bit saturating counter
                if (update_taken) begin
                    if (bht[bht_update_index] != 2'b11) begin
                        bht[bht_update_index] <= bht[bht_update_index] + 1;
                    end
                end else begin
                    if (bht[bht_update_index] != 2'b00) begin
                        bht[bht_update_index] <= bht[bht_update_index] - 1;
                    end
                end
                
                // Update BTB if branch was taken
                if (update_taken) begin
                    btb_targets[btb_update_index] <= update_target;
                    btb_tags[btb_update_index] <= btb_update_tag;
                    btb_valid[btb_update_index] <= 1'b1;
                end
                
                // Update performance counters
                total_predictions <= total_predictions + 1;
                
                // Check for misprediction
                if ((bht[bht_update_index][1] != update_taken) || 
                    (update_taken && (!btb_valid[btb_update_index] || 
                     btb_targets[btb_update_index] != update_target))) begin
                    total_mispredictions <= total_mispredictions + 1;
                end
            end
        end
    end

endmodule

// =============================================================================
// Fetch Queue
// =============================================================================
// Buffers fetched instructions between fetch and decode stages

module fetch_queue (
    input wire clk,
    input wire rst_n,
    
    // Input from fetch unit
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
    
    // Output to decode stage
    output wire [`XLEN-1:0] decode_pc1,
    output wire [`XLEN-1:0] decode_pc2,
    output wire [31:0] decode_instruction1,
    output wire [31:0] decode_instruction2,
    output wire decode_valid1,
    output wire decode_valid2,
    output wire decode_predicted_taken1,
    output wire decode_predicted_taken2,
    output wire [`XLEN-1:0] decode_predicted_target1,
    output wire [`XLEN-1:0] decode_predicted_target2,
    
    // Flow control
    input wire decode_ready,
    output wire fetch_ready,
    
    // Pipeline control
    input wire flush_queue,
    
    // Status
    output wire queue_full,
    output wire queue_empty,
    output wire [3:0] queue_entries
);

    // =============================================================================
    // Queue Storage
    // =============================================================================
    
    localparam ENTRY_WIDTH = `XLEN + 32 + 1 + 1 + `XLEN;  // PC + inst + valid + pred_taken + pred_target
    localparam QUEUE_ADDR_BITS = $clog2(`FETCH_QUEUE_SIZE);
    
    reg [`XLEN-1:0]         queue_pc        [`FETCH_QUEUE_SIZE-1:0];
    reg [31:0]              queue_inst      [`FETCH_QUEUE_SIZE-1:0];
    reg                     queue_valid     [`FETCH_QUEUE_SIZE-1:0];
    reg                     queue_pred_taken [`FETCH_QUEUE_SIZE-1:0];
    reg [`XLEN-1:0]         queue_pred_target [`FETCH_QUEUE_SIZE-1:0];
    
    reg [QUEUE_ADDR_BITS:0] head_ptr;
    reg [QUEUE_ADDR_BITS:0] tail_ptr;
    reg [QUEUE_ADDR_BITS:0] entry_count;
    
    // =============================================================================
    // Queue Management
    // =============================================================================
    
    wire can_enqueue1, can_enqueue2;
    wire can_dequeue1, can_dequeue2;
    wire [QUEUE_ADDR_BITS-1:0] head_idx, tail_idx;
    wire [QUEUE_ADDR_BITS-1:0] next_head, next_tail;
    
    assign head_idx = head_ptr[QUEUE_ADDR_BITS-1:0];
    assign tail_idx = tail_ptr[QUEUE_ADDR_BITS-1:0];
    assign next_head = (head_ptr + 1) % `FETCH_QUEUE_SIZE;
    assign next_tail = (tail_ptr + 1) % `FETCH_QUEUE_SIZE;
    
    assign can_enqueue1 = fetch_valid1 && (entry_count < `FETCH_QUEUE_SIZE);
    assign can_enqueue2 = fetch_valid2 && (entry_count < (`FETCH_QUEUE_SIZE - 1)) && can_enqueue1;
    
    assign can_dequeue1 = decode_ready && (entry_count > 0) && queue_valid[head_idx];
    assign can_dequeue2 = decode_ready && (entry_count > 1) && queue_valid[next_head] && can_dequeue1;
    
    // =============================================================================
    // Output Logic
    // =============================================================================
    
    assign decode_pc1 = queue_pc[head_idx];
    assign decode_pc2 = queue_pc[next_head];
    assign decode_instruction1 = queue_inst[head_idx];
    assign decode_instruction2 = queue_inst[next_head];
    assign decode_valid1 = can_dequeue1;
    assign decode_valid2 = can_dequeue2;
    assign decode_predicted_taken1 = queue_pred_taken[head_idx];
    assign decode_predicted_taken2 = queue_pred_taken[next_head];
    assign decode_predicted_target1 = queue_pred_target[head_idx];
    assign decode_predicted_target2 = queue_pred_target[next_head];
    
    assign fetch_ready = !queue_full;
    assign queue_full = (entry_count >= `FETCH_QUEUE_SIZE);
    assign queue_empty = (entry_count == 0);
    assign queue_entries = entry_count[3:0];
    
    // =============================================================================
    // Sequential Logic
    // =============================================================================
    
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= {(QUEUE_ADDR_BITS+1){1'b0}};
            tail_ptr <= {(QUEUE_ADDR_BITS+1){1'b0}};
            entry_count <= {(QUEUE_ADDR_BITS+1){1'b0}};
            
            for (i = 0; i < `FETCH_QUEUE_SIZE; i = i + 1) begin
                queue_pc[i] <= {`XLEN{1'b0}};
                queue_inst[i] <= 32'b0;
                queue_valid[i] <= 1'b0;
                queue_pred_taken[i] <= 1'b0;
                queue_pred_target[i] <= {`XLEN{1'b0}};
            end
        end
        else if (flush_queue) begin
            head_ptr <= {(QUEUE_ADDR_BITS+1){1'b0}};
            tail_ptr <= {(QUEUE_ADDR_BITS+1){1'b0}};
            entry_count <= {(QUEUE_ADDR_BITS+1){1'b0}};
            
            for (i = 0; i < `FETCH_QUEUE_SIZE; i = i + 1) begin
                queue_valid[i] <= 1'b0;
            end
        end
        else begin
            // Handle enqueue operations
            if (can_enqueue1) begin
                queue_pc[tail_idx] <= fetch_pc1;
                queue_inst[tail_idx] <= fetch_instruction1;
                queue_valid[tail_idx] <= 1'b1;
                queue_pred_taken[tail_idx] <= fetch_predicted_taken1;
                queue_pred_target[tail_idx] <= fetch_predicted_target1;
                
                tail_ptr <= next_tail;
                entry_count <= entry_count + 1;
            end
            
            if (can_enqueue2) begin
                queue_pc[next_tail] <= fetch_pc2;
                queue_inst[next_tail] <= fetch_instruction2;
                queue_valid[next_tail] <= 1'b1;
                queue_pred_taken[next_tail] <= fetch_predicted_taken2;
                queue_pred_target[next_tail] <= fetch_predicted_target2;
                
                tail_ptr <= (tail_ptr + 2) % `FETCH_QUEUE_SIZE;
                entry_count <= entry_count + 1;
            end
            
            // Handle dequeue operations
            if (can_dequeue1) begin
                queue_valid[head_idx] <= 1'b0;
                head_ptr <= next_head;
                entry_count <= entry_count - 1;
            end
            
            if (can_dequeue2) begin
                queue_valid[next_head] <= 1'b0;
                head_ptr <= (head_ptr + 2) % `FETCH_QUEUE_SIZE;
                entry_count <= entry_count - 1;
            end
        end
    end

endmodule