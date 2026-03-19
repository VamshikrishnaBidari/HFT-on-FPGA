`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.03.2026 09:51:30
// Design Name: 
// Module Name: hft_core
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

module hft_core (
    input logic clk,
    input logic reset,
    
    // Interface with UART
    input logic [7:0] rx_data,
    input logic rx_valid,
    output logic [7:0] tx_data,
    output logic tx_valid,
    
    // Debug
    output logic [7:0] debug_led
);

    // --- 1. Parser Interconnects ---
    logic [95:0] packet;
    logic comp_packet;
    
    // ADDED 'flags' back into the declarations
    logic [7:0] msg_type, side, flags; 
    logic [15:0] token, quantity;
    logic [23:0] price;
    logic parse_valid;

    // Instantiate Assembler
    packet_assembler ASSEMBLER (
        .clk(clk), 
        .reset(reset),
        .uart_byte(rx_data),
        .rx_data_valid(rx_valid), 
        .packet(packet),
        .packet_valid(comp_packet)
    );

    // Instantiate Parser
    parsing PARSER (
        .clk(clk), 
        .reset(reset),
        .packet_in(packet),             
        .packet_valid_in(comp_packet),  
        .msg_type(msg_type),
        .side(side),
        .token(token),
        .quantity(quantity),
        .price(price),
        .flags(flags),                  // NEW: Hooking up the flags output!
        .parse_valid(parse_valid)
    );

    // --- 2. Order Book Interconnects ---
    order_t      parsed_order;
    logic [23:0] best_bid;
    logic [23:0] best_ask; 
    logic [15:0] best_bid_qty;
    logic [15:0] best_ask_qty;
    logic        fifo_full;
    
    // FIX 1: Correctly pack the full 80-bit order_t struct!
    assign parsed_order.msg_type = msg_type;
    assign parsed_order.token    = token;
    assign parsed_order.side     = side;
    assign parsed_order.price    = price;
    assign parsed_order.quantity = quantity; // Strictly 16-bit!
    assign parsed_order.flags    = flags;

    order_book_top ORDER_BOOK (
        .clk(clk),
        .reset(reset),
        .packet_valid(parse_valid),
        .parsed_order(parsed_order),
        .best_bid(best_bid),         
        .best_bid_qty(best_bid_qty),
        .best_ask(best_ask),         
        .best_ask_qty(best_ask_qty),
        .fifo_full(fifo_full)
    );

    // --- 3. Trading Logic ---
    // Replaces the old temporary TX loopback
    trading_logic TRADING_STRATEGY (
        .clk(clk),
        .reset(reset),
        .best_bid(best_bid),
        .best_ask(best_ask),
        .book_busy(fifo_full),  // Backpressure stall passed to trading engine
        .tx_data(tx_data),      
        .tx_valid(tx_valid)     
    );

    // Update LEDs with the parsed Token ID for visual confirmation
    always_ff @(posedge clk) begin
        if (reset) debug_led <= 0;
        else if (parse_valid) debug_led <= token[7:0];
    end

endmodule
