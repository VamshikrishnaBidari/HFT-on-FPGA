`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.03.2026 11:19:53
// Design Name: 
// Module Name: tb_topk_cache
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_topk_cache();

    // -------------------------------------------------------------------------
    // Parameters & Signals
    // -------------------------------------------------------------------------
    localparam K = 4;
    localparam IS_BID = 1; // 1 = Bid Book (Highest price wins)

    logic        clk;
    logic        reset;
    
    logic        insert_valid;
    logic        cancel_valid;
    logic        execute_valid;
    
    logic [23:0] insert_price;
    logic [15:0] insert_quantity;
    logic [23:0] target_price;       // <--- RENAMED from cancel_price
    logic [15:0] execute_quantity;
    
    logic [23:0] bram_price;
    logic [15:0] bram_quantity;
    
    logic [23:0] best_price;
    logic [15:0] best_quantity;

    // -------------------------------------------------------------------------
    // Instantiate the Device Under Test (DUT)
    // -------------------------------------------------------------------------
    topk_cache #(
        .K(K),
        .IS_BID(IS_BID)
    ) dut (
        .clk(clk),
        .reset(reset),
        .insert_valid(insert_valid),
        .cancel_valid(cancel_valid),
        .execute_valid(execute_valid),
        .insert_price(insert_price),
        .insert_quantity(insert_quantity),
        .target_price(target_price), // <--- UPDATED MAPPING
        .execute_quantity(execute_quantity),
        .bram_price(bram_price),
        .bram_quantity(bram_quantity),
        .best_price(best_price),
        .best_quantity(best_quantity)
    );

    // -------------------------------------------------------------------------
    // Clock Generation (100 MHz for ZedBoard)
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk; // 10ns period

    // -------------------------------------------------------------------------
    // Helper Tasks for Market Events (Simulates the Parser FSM output)
    // Driven on negedge to avoid delta-cycle race conditions
    // -------------------------------------------------------------------------
    task insert_order(input [23:0] p, input [15:0] q);
        begin
            @(negedge clk);
            insert_valid    = 1;
            insert_price    = p;
            insert_quantity = q;
            @(negedge clk);
            insert_valid    = 0;
        end
    endtask

    task cancel_order(input [23:0] p, input [23:0] b_p, input [15:0] b_q);
        begin
            @(negedge clk);
            cancel_valid  = 1;
            target_price  = p;       // <--- UPDATED HERE
            bram_price    = b_p;
            bram_quantity = b_q;
            @(negedge clk);
            cancel_valid  = 0;
        end
    endtask

    task execute_order(input [23:0] p, input [15:0] q);
        begin
            @(negedge clk);
            execute_valid    = 1;
            target_price     = p;    // <--- UPDATED HERE
            execute_quantity = q;
            @(negedge clk);
            execute_valid    = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // 1. Initialize Default States
        reset            = 1;
        insert_valid     = 0;
        cancel_valid     = 0;
        execute_valid    = 0;
        insert_price     = 0;
        insert_quantity  = 0;
        target_price     = 0;        // <--- UPDATED HERE
        execute_quantity = 0;
        bram_price       = 0;
        bram_quantity    = 0;

        // 2. Apply Reset
        #50;
        @(posedge clk);
        reset = 0;
        #20;

        $display("\n--- Starting Top-K Cache Test (BID SIDE: Descending Sort) ---\n");

        // 3. Test O(1) Parallel Insertion
        $display("[TIME: %0t] Action: Inserting $100 (Qty: 50)", $time);
        insert_order(24'd100, 16'd50);
        #10;
        
        $display("[TIME: %0t] Action: Inserting $105 (Qty: 100) - Should become new Best Bid", $time);
        insert_order(24'd105, 16'd100);
        #10;
        
        $display("[TIME: %0t] Action: Inserting $102 (Qty: 25) - Should slide into middle", $time);
        insert_order(24'd102, 16'd25);
        #10;
        
        $display("[TIME: %0t] Action: Inserting $108 (Qty: 200) - Should become new Best Bid, shifting all down", $time);
        insert_order(24'd108, 16'd200);
        #20;

        // 4. Test In-Place Execution
        $display("[TIME: %0t] Action: Executing 50 shares of $108", $time);
        execute_order(24'd108, 16'd50);
        #20;

        // 5. Test O(1) Cancellation and BRAM Spillover
        $display("[TIME: %0t] Action: Canceling order at $105.", $time);
        $display("              -> Hardware should shift 102 & 100 up by one slot.");
        $display("              -> Hardware should fetch 5th best price ($99) from BRAM into slot K-1.");
        cancel_order(24'd105, 24'd99, 16'd10);
        #20;

        // 6. Test Canceling the Absolute Best Price
        $display("[TIME: %0t] Action: Canceling Top Order at $108.", $time);
        $display("              -> Best price should instantly drop to $102.");
        cancel_order(24'd108, 24'd98, 16'd5);
        #20;

        $display("\n--- Test Completed Successfully ---\n");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Console Monitor (Peeking inside the DUT array for verification)
    // -------------------------------------------------------------------------
    initial begin
        // The array indexing below prevents Vivado's 96-bit concatenation bug
        $monitor("   [STATE] Best Price: $%0d (Qty: %0d) | Full Cache Array: [ $%0d, $%0d, $%0d, $%0d ]", 
                 best_price, best_quantity, 
                 dut.price, dut.price[1], dut.price[2], dut.price[3]);
    end

endmodule