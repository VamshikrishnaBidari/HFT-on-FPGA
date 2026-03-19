`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.03.2026 08:31:54
// Design Name: 
// Module Name: sparse_bram_book
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


module sparse_bram_book #(
    parameter IS_BID = 1
)(
    input  logic        clk,
    input  logic        reset,
    
    // Inputs from FIFO
    input  logic        insert_valid,
    input  logic        cancel_valid,
    input  logic [23:0] price,
    input  logic [15:0] quantity,
    
    // Window Management
    input  logic [23:0] center_price,       // Used to center the 256-slot window
    input  logic [23:0] cache_bottom_price, // Used to mask the Priority Encoder
    
    // Spillover Outputs to Top-K Cache
    output logic [23:0] bram_price_out,
    output logic [15:0] bram_qty_out,
    output logic        busy
);

    // 1. The Bitmask and BRAM
    logic [255:0] price_mask;
    
    // Force Vivado to map this to Block RAM (True Dual Port)
    (* ram_style = "block" *) logic [15:0] qty_bram [0:255]; 
    
    // 2. Window Index Calculation (Fixed-Point Integer Math)
    logic signed [24:0] price_diff;
    logic signed [24:0] target_index_signed;
    logic [7:0]         target_index;
    logic               out_of_bounds;

    assign price_diff          = $signed({1'b0, price}) - $signed({1'b0, center_price});
    assign target_index_signed = price_diff + 128;
    assign out_of_bounds       = (target_index_signed < 0 || target_index_signed > 255);
    assign target_index        = target_index_signed[7:0];

    // 3. Dual-Port BRAM Interfaces
    logic        we_A;
    logic [7:0]  addr_A;
    logic [15:0] din_A;
    logic [15:0] dout_A; // Read result for FSM
    
    logic [7:0]  addr_B; // Read address for Top-K spillover

    // Port A (Read-Modify-Write for Inserts/Cancels)
    always_ff @(posedge clk) begin
        if (we_A) qty_bram[addr_A] <= din_A;
        dout_A <= qty_bram[addr_A];
    end

    // Port B (Continuous Read for Top-K Spillover)
    always_ff @(posedge clk) begin
        bram_qty_out <= qty_bram[addr_B];
    end

    // 4. Priority Encoder Instantiation
    logic [7:0] cache_bottom_index;
    logic       spillover_valid;
    
    // Convert cache's worst price to an index for the encoder limit
    assign cache_bottom_index = ($signed({1'b0, cache_bottom_price}) - $signed({1'b0, center_price})) + 128;

    bitmask_encoder #(.IS_BID(IS_BID)) ENCODER (
        .mask(price_mask),
        .limit_index(cache_bottom_index),
        .best_index(addr_B), // Feed directly to BRAM Port B
        .valid(spillover_valid)
    );
    
    // Reverse calculate the price from the index to feed the Top-K cache
    assign bram_price_out = (spillover_valid) ? (center_price + addr_B - 128) : (IS_BID ? 24'd0 : 24'hFFFFFF);

    // 5. Background O(1) FSM for Add/Cancel
    typedef enum logic {IDLE, MODIFY_MEM} state_t;
    state_t state;
    
    logic is_insert_op; // Remembers if current op is insert or cancel
    logic [15:0] pending_qty;

    always_ff @(posedge clk) begin
        if (reset) begin
            state      <= IDLE;
            busy       <= 0;
            price_mask <= 256'd0;
            we_A       <= 0;
            
            // Note: BRAM contents are uninitialized in hardware, but mask is 0 so it's safe.
        end else begin
            case (state)
                IDLE: begin
                    we_A <= 0;
                    if ((insert_valid || cancel_valid) && !out_of_bounds) begin
                        busy         <= 1; // Stall the Input FIFO
                        addr_A       <= target_index; // Trigger Port A Read
                        pending_qty  <= quantity;
                        is_insert_op <= insert_valid;
                        state        <= MODIFY_MEM;
                    end else begin
                        busy <= 0;
                    end
                end
                
                MODIFY_MEM: begin
                    // Data from Port A Read is now ready in dout_A
                    we_A   <= 1; // Enable Write
                    addr_A <= addr_A; 
                    
                    if (is_insert_op) begin
                        din_A <= dout_A + pending_qty;
                        price_mask[addr_A] <= 1'b1; // Mark Valid
                    end else begin
                        // Cancel Operation (subtract quantity safely)
                        if (dout_A <= pending_qty) begin
                            din_A <= 0;
                            price_mask[addr_A] <= 1'b0; // Lazy Deletion!
                        end else begin
                            din_A <= dout_A - pending_qty;
                        end
                    end
                    
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
