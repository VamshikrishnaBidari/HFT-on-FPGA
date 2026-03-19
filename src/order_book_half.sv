`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.03.2026 12:24:50
// Design Name: 
// Module Name: order_book_half
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


`timescale 1ns / 1ps
import hft_types::*; // BRINGING BACK THE STRUCTS!

module order_book_half #(
    parameter IS_BID = 1
)(
    input  logic        clk,
    input  logic        reset,

    // From Top-Level Router (Parser Output)
    input  logic        packet_valid,
    input  order_t      parsed_order_in,
    output logic        fifo_full,

    // Output to Trading Logic
    output logic [23:0] best_price,
    output logic [15:0] best_quantity
);

    // ---------------------------------------------------------
    // 1. The Backpressure FIFO
    // ---------------------------------------------------------
    logic   fifo_empty, fifo_rd_en;
    order_t current_order; // Struct pulled from FIFO

    sync_fifo #(.WIDTH(80), .DEPTH(512)) INPUT_FIFO (
        .clk(clk), .reset(reset),
        .wr_en(packet_valid), .din(parsed_order_in), .full(fifo_full),
        .rd_en(fifo_rd_en), .dout(current_order), .empty(fifo_empty)
    );

    // ---------------------------------------------------------
    // 2. Order ID Hash Map (For Cancels/Trades)
    // ---------------------------------------------------------
    logic        hash_we;
    logic [23:0] hash_rd_price;
    logic [15:0] hash_rd_qty;

    order_id_map HASH_MAP (
        .clk(clk),
        .we(hash_we),
        .wr_order_id(current_order.token),
        .wr_price(current_order.price),
        .wr_qty(current_order.quantity),
        .rd_order_id(current_order.token),
        .rd_price(hash_rd_price),
        .rd_qty(hash_rd_qty)
    );

    // ---------------------------------------------------------
    // 3. Circular BRAM & Top-K Storage
    // ---------------------------------------------------------
    logic        insert_valid, cancel_valid;
    logic [23:0] active_price;
    logic [15:0] active_qty;
    logic        bram_busy;
    
    logic [23:0] bram_spill_price;
    logic [15:0] bram_spill_qty;
    logic [23:0] cache_bottom_price;

    circular_sparse_bram #(.IS_BID(IS_BID)) BRAM_BOOK (
        .clk(clk), .reset(reset),
        .insert_valid(insert_valid), .cancel_valid(cancel_valid),
        .price(active_price), .quantity(active_qty),
        .cache_bottom_price(cache_bottom_price),
        .bram_price_out(bram_spill_price), .bram_qty_out(bram_spill_qty),
        .busy(bram_busy)
    );

    topk_cache #(.K(4), .IS_BID(IS_BID)) TOP_K_CACHE (
        .clk(clk), .reset(reset),
        .insert_valid(insert_valid), .cancel_valid(cancel_valid), .execute_valid(1'b0),
        .insert_price(active_price), .insert_quantity(active_qty),
        .target_price(active_price), .execute_quantity(16'd0),
        .bram_price(bram_spill_price), .bram_quantity(bram_spill_qty),
        .best_price(best_price), .best_quantity(best_quantity),
        .bottom_price(cache_bottom_price)
    );

    // ---------------------------------------------------------
    // 4. Control FSM (FIFO Pop -> Hash Lookup -> BRAM Feed)
    // ---------------------------------------------------------
    ctrl_state_t ctrl_state;

    always_ff @(posedge clk) begin
        if (reset) begin
            ctrl_state   <= POP_FIFO;
            fifo_rd_en   <= 0;
            hash_we      <= 0;
            insert_valid <= 0;
            cancel_valid <= 0;
        end else begin
            // Defaults
            fifo_rd_en   <= 0;
            hash_we      <= 0;
            insert_valid <= 0;
            cancel_valid <= 0;

            case (ctrl_state)
                POP_FIFO: begin
                    // Only pop if book is ready to accept and FIFO has data
                    if (!fifo_empty && !bram_busy) begin
                        fifo_rd_en <= 1; 
                        ctrl_state <= HASH_LOOKUP;
                    end
                end

                HASH_LOOKUP: begin
                    // BRAM takes 1 cycle to read the Hash Map. 
                    // If it's an Add ('N' = 8'h4E), trigger the Write-Enable for Hash Map.
                    if (current_order.msg_type == 8'h4E) hash_we <= 1; 
                    ctrl_state <= FIRE_BOOK;
                end

                FIRE_BOOK: begin
                    if (current_order.msg_type == 8'h4E) begin 
                        // ADD: Use price straight from packet
                        active_price <= current_order.price;
                        active_qty   <= current_order.quantity;
                        insert_valid <= 1;
                    end else if (current_order.msg_type == 8'h58 || current_order.msg_type == 8'h54) begin 
                        // CANCEL/TRADE: Substitute price with data fetched from Hash Map
                        active_price <= hash_rd_price; 
                        active_qty   <= current_order.quantity; 
                        cancel_valid <= 1;
                    end
                    ctrl_state <= POP_FIFO;
                end
            endcase
        end
    end
endmodule