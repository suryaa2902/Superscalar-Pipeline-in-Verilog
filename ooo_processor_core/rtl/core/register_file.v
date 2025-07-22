// =============================================================================
// Physical Register File
// =============================================================================
// File: register_file.v
// Description: Multi-ported physical register file for out-of-order processor
// Author: Suryaa Senthilkumar Shanthi
// Date: 8 July 2025
// =============================================================================

`include "ooo_processor_defines.vh"

module register_file (
    input wire clk,
    input wire rst_n,
    
    // Read ports (multiple for superscalar)
    input wire [`PHYS_REG_BITS-1:0] read_addr1,
    input wire [`PHYS_REG_BITS-1:0] read_addr2,
    input wire [`PHYS_REG_BITS-1:0] read_addr3,
    input wire [`PHYS_REG_BITS-1:0] read_addr4,
    input wire read_enable1,
    input wire read_enable2,
    input wire read_enable3,
    input wire read_enable4,
    
    output reg [`XLEN-1:0] read_data1,
    output reg [`XLEN-1:0] read_data2,
    output reg [`XLEN-1:0] read_data3,
    output reg [`XLEN-1:0] read_data4,
    
    // Write ports (multiple for superscalar)
    input wire [`PHYS_REG_BITS-1:0] write_addr1,
    input wire [`PHYS_REG_BITS-1:0] write_addr2,
    input wire [`XLEN-1:0] write_data1,
    input wire [`XLEN-1:0] write_data2,
    input wire write_enable1,
    input wire write_enable2,
    
    // Register ready bits (for dependency tracking)
    input wire [`PHYS_REG_BITS-1:0] ready_addr1,
    input wire [`PHYS_REG_BITS-1:0] ready_addr2,
    input wire ready_set1,
    input wire ready_set2,
    input wire ready_clear1,
    input wire ready_clear2,
    
    output wire ready_out1,
    output wire ready_out2,
    
    // Free list interface
    input wire [`PHYS_REG_BITS-1:0] free_reg_addr,
    input wire free_reg_enable,
    
    // Debug interface
    output wire [`PHYS_REGS-1:0] debug_ready_bits
);

    // =============================================================================
    // Internal Registers
    // =============================================================================
    
    // Physical register file storage
    reg [`XLEN-1:0] registers [`PHYS_REGS-1:0];
    
    // Ready bits for each physical register
    reg [`PHYS_REGS-1:0] ready_bits;
    
    // =============================================================================
    // Initialization
    // =============================================================================
    
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize all registers to zero
            for (i = 0; i < `PHYS_REGS; i = i + 1) begin
                registers[i] <= {`XLEN{1'b0}};
            end
            
            // Initialize ready bits - first 32 registers (architectural) are ready
            ready_bits <= {{(`PHYS_REGS-`ARCH_REGS){1'b0}}, {`ARCH_REGS{1'b1}}};
        end
        else begin
            // Write operations
            if (write_enable1) begin
                registers[write_addr1] <= write_data1;
            end
            
            if (write_enable2) begin
                registers[write_addr2] <= write_data2;
            end
            
            // Ready bit management
            if (ready_set1) begin
                ready_bits[ready_addr1] <= 1'b1;
            end
            if (ready_clear1) begin
                ready_bits[ready_addr1] <= 1'b0;
            end
            
            if (ready_set2) begin
                ready_bits[ready_addr2] <= 1'b1;
            end
            if (ready_clear2) begin
                ready_bits[ready_addr2] <= 1'b0;
            end
            
            // Free register (mark as ready for reuse)
            if (free_reg_enable) begin
                ready_bits[free_reg_addr] <= 1'b1;
                registers[free_reg_addr] <= {`XLEN{1'b0}};
            end
        end
    end
    
    // =============================================================================
    // Read Operations (Combinational)
    // =============================================================================
    
    always @(*) begin
        // Read port 1
        if (read_enable1) begin
            read_data1 = registers[read_addr1];
        end else begin
            read_data1 = {`XLEN{1'b0}};
        end
        
        // Read port 2
        if (read_enable2) begin
            read_data2 = registers[read_addr2];
        end else begin
            read_data2 = {`XLEN{1'b0}};
        end
        
        // Read port 3
        if (read_enable3) begin
            read_data3 = registers[read_addr3];
        end else begin
            read_data3 = {`XLEN{1'b0}};
        end
        
        // Read port 4
        if (read_enable4) begin
            read_data4 = registers[read_addr4];
        end else begin
            read_data4 = {`XLEN{1'b0}};
        end
    end
    
    // =============================================================================
    // Ready Bit Outputs
    // =============================================================================
    
    assign ready_out1 = ready_bits[ready_addr1];
    assign ready_out2 = ready_bits[ready_addr2];
    
    // =============================================================================
    // Debug Interface
    // =============================================================================
    
    assign debug_ready_bits = ready_bits;
    
    // =============================================================================
    // Assertions for Debugging (Synthesis Safe)
    // =============================================================================
    
    // synthesis translate_off
    always @(posedge clk) begin
        if (rst_n) begin
            // Check for write conflicts
            if (write_enable1 && write_enable2 && (write_addr1 == write_addr2)) begin
                $display("WARNING: Write conflict detected at register %d", write_addr1);
            end
            
            // Check for out-of-bounds access
            if (read_enable1 && (read_addr1 >= `PHYS_REGS)) begin
                $display("ERROR: Out-of-bounds read access at address %d", read_addr1);
            end
            
            if (write_enable1 && (write_addr1 >= `PHYS_REGS)) begin
                $display("ERROR: Out-of-bounds write access at address %d", write_addr1);
            end
        end
    end
    // synthesis translate_on

endmodule

// =============================================================================
// Free List Manager
// =============================================================================
// Manages the pool of available physical registers

module free_list_manager (
    input wire clk,
    input wire rst_n,
    
    // Allocation interface
    input wire allocate_req1,
    input wire allocate_req2,
    output wire [`PHYS_REG_BITS-1:0] allocated_reg1,
    output wire [`PHYS_REG_BITS-1:0] allocated_reg2,
    output wire allocation_valid1,
    output wire allocation_valid2,
    
    // Deallocation interface
    input wire [`PHYS_REG_BITS-1:0] free_reg1,
    input wire [`PHYS_REG_BITS-1:0] free_reg2,
    input wire free_enable1,
    input wire free_enable2,
    
    // Status
    output wire [`PHYS_REG_BITS:0] free_count,
    output wire free_list_empty,
    output wire free_list_full
);

    // =============================================================================
    // Internal Storage
    // =============================================================================
    
    // Free list storage (circular buffer)
    reg [`PHYS_REG_BITS-1:0] free_list [`PHYS_REGS-1:0];
    
    // Pointers for circular buffer
    reg [`PHYS_REG_BITS:0] head_ptr;
    reg [`PHYS_REG_BITS:0] tail_ptr;
    reg [`PHYS_REG_BITS:0] count;
    
    // =============================================================================
    // Initialization
    // =============================================================================
    
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize free list with non-architectural registers
            for (i = 0; i < (`PHYS_REGS - `ARCH_REGS); i = i + 1) begin
                free_list[i] <= `ARCH_REGS + i;
            end
            
            head_ptr <= 0;
            tail_ptr <= `PHYS_REGS - `ARCH_REGS;
            count <= `PHYS_REGS - `ARCH_REGS;
        end
        else begin
            // Handle allocations
            if (allocate_req1 && allocation_valid1) begin
                head_ptr <= (head_ptr + 1) % `PHYS_REGS;
                count <= count - 1;
            end
            
            if (allocate_req2 && allocation_valid2) begin
                head_ptr <= (head_ptr + 1) % `PHYS_REGS;
                count <= count - 1;
            end
            
            // Handle deallocations
            if (free_enable1) begin
                free_list[tail_ptr] <= free_reg1;
                tail_ptr <= (tail_ptr + 1) % `PHYS_REGS;
                count <= count + 1;
            end
            
            if (free_enable2) begin
                free_list[tail_ptr] <= free_reg2;
                tail_ptr <= (tail_ptr + 1) % `PHYS_REGS;
                count <= count + 1;
            end
        end
    end
    
    // =============================================================================
    // Output Logic
    // =============================================================================
    
    assign allocated_reg1 = free_list[head_ptr];
    assign allocated_reg2 = free_list[(head_ptr + 1) % `PHYS_REGS];
    
    assign allocation_valid1 = (count > 0) && allocate_req1;
    assign allocation_valid2 = (count > 1) && allocate_req2 && allocate_req1;
    
    assign free_count = count;
    assign free_list_empty = (count == 0);
    assign free_list_full = (count == `PHYS_REGS);

endmodule
