`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 19.02.2026 19:29:11
// Design Name: 
// Module Name: order_book
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
import hft_types::*;

module order_book_top (
    input logic clk,
    input logic reset,
    
    // Inputs from Parser
    input logic new_packet,
    input logic [7:0] msg_type, // 'N', 'X', 'T'
    input logic [7:0] side,     // 'B' (0x42) or 'S' (0x53)
    input order_t parsed_order,
    
    // Outputs to Trading Logic
    output logic [23:0] best_bid,
    output logic [23:0] best_ask,
    output logic busy
);

    // Independent routing signals
    logic bid_start, ask_start;
    logic bid_busy, ask_busy;
    
    // The top module is busy if either half is busy
    assign busy = bid_busy | ask_busy;

    // Combinational Router: Direct packets to the correct book
    always_comb begin
        bid_start = 0;
        ask_start = 0;
        
        if (new_packet) begin
            if (side == 8'h42) begin // Hex 42 is 'B' (Buy)
                bid_start = 1;
            end else if (side == 8'h53) begin // Hex 53 is 'S' (Sell)
                ask_start = 1;
            end
        end
    end

    // ---------------------------------------------------------
    // Instantiate the Bid Half (Buys - Seeks Maximum Price)
    // ---------------------------------------------------------
    order_book_half #(.IS_BID(1)) BID_BOOK (
        .clk(clk),
        .reset(reset),
        .new_packet(bid_start),
        .msg_type(msg_type),
        .parsed_order(parsed_order),
        .best_price(best_bid),
        .busy(bid_busy)
    );

    // ---------------------------------------------------------
    // Instantiate the Ask Half (Sells - Seeks Minimum Price)
    // ---------------------------------------------------------
    order_book_half #(.IS_BID(0)) ASK_BOOK (
        .clk(clk),
        .reset(reset),
        .new_packet(ask_start),
        .msg_type(msg_type),
        .parsed_order(parsed_order),
        .best_price(best_ask),
        .busy(ask_busy)
    );

endmodule
