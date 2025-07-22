// =============================================================================
// Out-of-Order Processor Testbench
// =============================================================================
// File: tb_ooo_processor.v
// Description: Comprehensive testbench for out-of-order processor
// Author: [Your Name]
// Date: [Current Date]
// =============================================================================

`timescale 1ns / 1ps
`include "../rtl/packages/ooo_processor_defines.vh"

module tb_ooo_processor;

    // =============================================================================
    // Testbench Signals
    // =============================================================================
    
    // Loop variables (declared at module level for Verilog-2001 compatibility)
    integer i;
    
    // Clock and reset
    reg clk;
    reg rst_n;
    
    // Memory interfaces
    wire [31:0] imem_addr;
    wire imem_req;
    reg [63:0] imem_data;
    reg imem_valid;
    reg imem_ready;
    
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0] dmem_be;
    wire dmem_we;
    wire dmem_req;
    reg [31:0] dmem_rdata;
    reg dmem_valid;
    reg dmem_ready;
    
    // Debug and status
    wire [31:0] debug_pc;
    wire [31:0] debug_instruction;
    wire debug_instruction_valid;
    wire [31:0] committed_instructions;
    wire processor_idle;
    wire [31:0] total_cycles;
    wire [31:0] stall_cycles;
    wire [31:0] flush_cycles;
    
    // =============================================================================
    // Simple Memory Models
    // =============================================================================
    
    // Instruction memory (simple ROM)
    reg [31:0] instruction_memory [0:1023];  // 4KB instruction memory
    reg [31:0] data_memory [0:1023];         // 4KB data memory
    
    // Memory response delays
    reg [2:0] imem_delay_counter;
    reg [2:0] dmem_delay_counter;
    reg imem_pending;
    reg dmem_pending;
    reg [31:0] pending_imem_addr;
    reg [31:0] pending_dmem_addr;
    
    // =============================================================================
    // DUT Instantiation
    // =============================================================================
    
    ooo_processor_top dut (
        .clk(clk),
        .rst_n(rst_n),
        
        // External memory interface
        .imem_addr(imem_addr),
        .imem_req(imem_req),
        .imem_data(imem_data),
        .imem_valid(imem_valid),
        .imem_ready(imem_ready),
        
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_be(dmem_be),
        .dmem_we(dmem_we),
        .dmem_req(dmem_req),
        .dmem_rdata(dmem_rdata),
        .dmem_valid(dmem_valid),
        .dmem_ready(dmem_ready),
        
        // Debug and status outputs
        .debug_pc(debug_pc),
        .debug_instruction(debug_instruction),
        .debug_instruction_valid(debug_instruction_valid),
        .committed_instructions(committed_instructions),
        .processor_idle(processor_idle),
        .total_cycles(total_cycles),
        .stall_cycles(stall_cycles),
        .flush_cycles(flush_cycles)
    );
    
    // =============================================================================
    // Clock Generation
    // =============================================================================
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock (10ns period)
    end
    
    // =============================================================================
    // Instruction Memory Model
    // =============================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_delay_counter <= 0;
            imem_pending <= 0;
            imem_valid <= 0;
            imem_ready <= 1;
            pending_imem_addr <= 0;
        end
        else begin
            // Handle new instruction memory requests
            if (imem_req && imem_ready && !imem_pending) begin
                imem_pending <= 1;
                imem_ready <= 0;
                pending_imem_addr <= imem_addr;
                imem_delay_counter <= 1;  // 1 cycle latency
            end
            
            // Handle pending requests
            if (imem_pending) begin
                if (imem_delay_counter == 0) begin
                    // Return instruction data (2 instructions = 64 bits)
                    imem_data <= {instruction_memory[pending_imem_addr[11:2] + 1], 
                                 instruction_memory[pending_imem_addr[11:2]]};
                    imem_valid <= 1;
                    imem_pending <= 0;
                    imem_ready <= 1;
                end
                else begin
                    imem_delay_counter <= imem_delay_counter - 1;
                end
            end
            else begin
                imem_valid <= 0;
            end
        end
    end
    
    // =============================================================================
    // Data Memory Model
    // =============================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_delay_counter <= 0;
            dmem_pending <= 0;
            dmem_valid <= 0;
            dmem_ready <= 1;
            pending_dmem_addr <= 0;
            
            // Initialize data memory
            for (i = 0; i < 1024; i = i + 1) begin
                data_memory[i] <= i * 4;  // Simple pattern
            end
        end
        else begin
            // Handle new data memory requests
            if (dmem_req && dmem_ready && !dmem_pending) begin
                dmem_pending <= 1;
                dmem_ready <= 0;
                pending_dmem_addr <= dmem_addr;
                dmem_delay_counter <= 2;  // 2 cycle latency for data memory
                
                // Handle writes immediately
                if (dmem_we) begin
                    if (dmem_be[0]) data_memory[dmem_addr[11:2]][7:0]   <= dmem_wdata[7:0];
                    if (dmem_be[1]) data_memory[dmem_addr[11:2]][15:8]  <= dmem_wdata[15:8];
                    if (dmem_be[2]) data_memory[dmem_addr[11:2]][23:16] <= dmem_wdata[23:16];
                    if (dmem_be[3]) data_memory[dmem_addr[11:2]][31:24] <= dmem_wdata[31:24];
                end
            end
            
            // Handle pending requests
            if (dmem_pending) begin
                if (dmem_delay_counter == 0) begin
                    // Return data for loads
                    dmem_rdata <= data_memory[pending_dmem_addr[11:2]];
                    dmem_valid <= 1;
                    dmem_pending <= 0;
                    dmem_ready <= 1;
                end
                else begin
                    dmem_delay_counter <= dmem_delay_counter - 1;
                end
            end
            else begin
                dmem_valid <= 0;
            end
        end
    end
    
    // =============================================================================
    // Test Program Loading
    // =============================================================================
    
    task load_test_program;
        input integer test_num;
        begin
            case (test_num)
                1: load_simple_alu_test();
                2: load_load_store_test();
                3: load_branch_test();
                4: load_data_dependency_test();
                5: load_comprehensive_test();
                default: load_simple_alu_test();
            endcase
        end
    endtask
    
    // Test 1: Simple ALU operations
    task load_simple_alu_test;
        begin
            $display("Loading Simple ALU Test Program");
            
            // ADDI x1, x0, 10      # x1 = 10
            instruction_memory[0] = 32'h00a00093;
            
            // ADDI x2, x0, 20      # x2 = 20
            instruction_memory[1] = 32'h01400113;
            
            // ADD x3, x1, x2       # x3 = x1 + x2 = 30
            instruction_memory[2] = 32'h002081b3;
            
            // SUB x4, x3, x1       # x4 = x3 - x1 = 20
            instruction_memory[3] = 32'h40118233;
            
            // AND x5, x3, x2       # x5 = x3 & x2
            instruction_memory[4] = 32'h0021f2b3;
            
            // OR x6, x4, x5        # x6 = x4 | x5
            instruction_memory[5] = 32'h00526333;
            
            // XOR x7, x1, x2       # x7 = x1 ^ x2
            instruction_memory[6] = 32'h0020c3b3;
            
            // NOP (ADDI x0, x0, 0)
            instruction_memory[7] = 32'h00000013;
            
            // Clear remaining memory
            for (i = 8; i < 1024; i = i + 1) begin
                instruction_memory[i] = 32'h00000013; // NOP
            end
        end
    endtask
    
    // Test 2: Load/Store operations
    task load_load_store_test;
        begin
            $display("Loading Load/Store Test Program");
            
            // ADDI x1, x0, 100     # x1 = 100 (base address)
            instruction_memory[0] = 32'h06400093;
            
            // ADDI x2, x0, 42      # x2 = 42 (test data)
            instruction_memory[1] = 32'h02a00113;
            
            // SW x2, 0(x1)         # Store x2 to memory[x1]
            instruction_memory[2] = 32'h0020a023;
            
            // LW x3, 0(x1)         # Load from memory[x1] to x3
            instruction_memory[3] = 32'h0000a183;
            
            // ADDI x4, x0, 4       # x4 = 4 (offset)
            instruction_memory[4] = 32'h00400213;
            
            // SW x3, 4(x1)         # Store x3 to memory[x1+4]
            instruction_memory[5] = 32'h0030a223;
            
            // LW x5, 4(x1)         # Load from memory[x1+4] to x5
            instruction_memory[6] = 32'h0040a283;
            
            // Clear remaining memory
            for (i = 7; i < 1024; i = i + 1) begin
                instruction_memory[i] = 32'h00000013; // NOP
            end
        end
    endtask
    
    // Test 3: Branch operations
    task load_branch_test;
        begin
            $display("Loading Branch Test Program");
            
            // ADDI x1, x0, 10      # x1 = 10
            instruction_memory[0] = 32'h00a00093;
            
            // ADDI x2, x0, 20      # x2 = 20
            instruction_memory[1] = 32'h01400113;
            
            // BEQ x1, x2, skip     # Branch if x1 == x2 (should not branch)
            instruction_memory[2] = 32'h00208463;
            
            // ADD x3, x1, x2       # x3 = x1 + x2 (should execute)
            instruction_memory[3] = 32'h002081b3;
            
            // skip: ADDI x4, x0, 99 # x4 = 99
            instruction_memory[4] = 32'h06300213;
            
            // BNE x1, x2, end      # Branch if x1 != x2 (should branch)
            instruction_memory[5] = 32'h00209463;
            
            // ADDI x5, x0, 88      # x5 = 88 (should be skipped)
            instruction_memory[6] = 32'h05800293;
            
            // end: ADDI x6, x0, 77 # x6 = 77
            instruction_memory[7] = 32'h04d00313;
            
            // Clear remaining memory
            for (i = 8; i < 1024; i = i + 1) begin
                instruction_memory[i] = 32'h00000013; // NOP
            end
        end
    endtask
    
    // Test 4: Data dependency test
    task load_data_dependency_test;
        begin
            $display("Loading Data Dependency Test Program");
            
            // ADDI x1, x0, 5       # x1 = 5
            instruction_memory[0] = 32'h00500093;
            
            // ADDI x2, x1, 3       # x2 = x1 + 3 = 8 (RAW dependency)
            instruction_memory[1] = 32'h00308113;
            
            // ADD x3, x1, x2       # x3 = x1 + x2 = 13 (RAW dependencies)
            instruction_memory[2] = 32'h002081b3;
            
            // SUB x4, x3, x1       # x4 = x3 - x1 = 8 (RAW dependencies)
            instruction_memory[3] = 32'h40118233;
            
            // OR x5, x2, x4        # x5 = x2 | x4 (RAW dependencies)
            instruction_memory[4] = 32'h004162b3;
            
            // AND x6, x5, x3       # x6 = x5 & x3 (RAW dependencies)
            instruction_memory[5] = 32'h0032f333;
            
            // Clear remaining memory
            for (i = 6; i < 1024; i = i + 1) begin
                instruction_memory[i] = 32'h00000013; // NOP
            end
        end
    endtask
    
    // Test 5: Comprehensive test
    task load_comprehensive_test;
        begin
            $display("Loading Comprehensive Test Program");
            
            // Mix of ALU, load/store, and branches
            // ADDI x1, x0, 16      # x1 = 16
            instruction_memory[0] = 32'h01000093;
            
            // ADDI x2, x0, 32      # x2 = 32
            instruction_memory[1] = 32'h02000113;
            
            // ADD x3, x1, x2       # x3 = 48
            instruction_memory[2] = 32'h002081b3;
            
            // SW x3, 0(x1)         # Store x3 to memory[16]
            instruction_memory[3] = 32'h0030a023;
            
            // LW x4, 0(x1)         # Load from memory[16] to x4
            instruction_memory[4] = 32'h0000a203;
            
            // BEQ x3, x4, match    # Should branch (x3 == x4)
            instruction_memory[5] = 32'h00418463;
            
            // ADDI x5, x0, 999     # Should be skipped
            instruction_memory[6] = 32'h3e700293;
            
            // match: SUB x5, x4, x1 # x5 = x4 - x1 = 32
            instruction_memory[7] = 32'h40120293;
            
            // XOR x6, x2, x5       # x6 = x2 ^ x5 = 0
            instruction_memory[8] = 32'h00514333;
            
            // Clear remaining memory
            for (i = 9; i < 1024; i = i + 1) begin
                instruction_memory[i] = 32'h00000013; // NOP
            end
        end
    endtask
    
    // =============================================================================
    // Test Execution and Monitoring
    // =============================================================================
    
    task run_test;
        input integer test_num;
        input integer max_cycles;
        begin
            $display("========================================");
            $display("Running Test %0d", test_num);
            $display("========================================");
            
            // Reset processor
            rst_n = 0;
            #20;
            rst_n = 1;
            #10;
            
            // Load test program
            load_test_program(test_num);
            
            // Run simulation with timeout
            begin : timeout_block
                fork
                    // Timeout watchdog
                    begin : watchdog
                        #(max_cycles * 10);
                        $display("ERROR: Test %0d timed out after %0d cycles", test_num, max_cycles);
                        $finish;
                    end
                    
                    // Monitor execution
                    begin : monitor
                        while (!processor_idle || committed_instructions < 5) begin
                            @(posedge clk);
                            
                            if (debug_instruction_valid) begin
                                $display("Cycle %0d: PC=0x%08h, Inst=0x%08h, Committed=%0d", 
                                       total_cycles, debug_pc, debug_instruction, committed_instructions);
                            end
                            
                            // Stop if we've committed enough instructions
                            if (committed_instructions >= 8) begin
                                disable watchdog;
                                $finish;
                            end
                        end
                        disable watchdog;
                    end
                join
            end
            
            // Print results
            $display("Test %0d completed:", test_num);
            $display("  Total cycles: %0d", total_cycles);
            $display("  Committed instructions: %0d", committed_instructions);
            $display("  Stall cycles: %0d", stall_cycles);
            $display("  Flush cycles: %0d", flush_cycles);
            if (total_cycles > 0) begin
                $display("  IPC: %0d.%02d", committed_instructions * 100 / total_cycles / 100, 
                        (committed_instructions * 100 / total_cycles) % 100);
            end
            $display("");
        end
    endtask
    
    // =============================================================================
    // Register File Monitoring
    // =============================================================================
    
    task display_register_state;
        begin
            $display("Register File State:");
            // Note: This would require debug access to register file
            // For now, we monitor through committed instruction results
        end
    endtask
    
    // =============================================================================
    // Main Test Sequence
    // =============================================================================
    
    initial begin
        $display("========================================");
        $display("Out-of-Order Processor Testbench");
        $display("========================================");
        
        // Initialize signals
        rst_n = 0;
        imem_data = 0;
        imem_valid = 0;
        imem_ready = 1;
        dmem_rdata = 0;
        dmem_valid = 0;
        dmem_ready = 1;
        
        // Wait for reset deassertion
        #50;
        
        // Run all tests
        run_test(1, 1000);  // Simple ALU test
        #100;
        
        run_test(2, 1000);  // Load/Store test
        #100;
        
        run_test(3, 1000);  // Branch test
        #100;
        
        run_test(4, 1000);  // Data dependency test
        #100;
        
        run_test(5, 1500);  // Comprehensive test
        #100;
        
        $display("========================================");
        $display("All tests completed successfully!");
        $display("========================================");
        
        $finish;
    end
    
    // =============================================================================
    // Waveform Dumping
    // =============================================================================
    
    initial begin
        $dumpfile("ooo_processor_test.vcd");
        $dumpvars(0, tb_ooo_processor);
    end
    
    // =============================================================================
    // Error Checking
    // =============================================================================
    
    // Monitor for any X's or Z's in critical signals
    always @(posedge clk) begin
        if (rst_n) begin
            if (^debug_pc === 1'bx) begin
                $display("ERROR: X detected in debug_pc at time %0t", $time);
            end
            
            if (^committed_instructions === 1'bx) begin
                $display("ERROR: X detected in committed_instructions at time %0t", $time);
            end
        end
    end

endmodule
