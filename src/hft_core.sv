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
    order_t parsed_order;
    logic [23:0] best_bid;
    logic [23:0] best_ask; // NEW: Wire to catch the Best Ask from the Sell Book
    logic book_busy;
    
    // Pack the raw 1D Verilog wires into the SystemVerilog struct 
    assign parsed_order.price = price;
    assign parsed_order.order_id = token;
    assign parsed_order.quantity = quantity[7:0]; // Casting 16-bit to 8-bit to fit our struct

    // Instantiate Order Book
    order_book_top ORDER_BOOK (
        .clk(clk),
        .reset(reset),
        .new_packet(parse_valid),
        .msg_type(msg_type),
        .side(side),                 // FIXED: Connect the side so it routes to Bid or Ask
        .parsed_order(parsed_order),
        .best_bid(best_bid),         // Connects the highest buy price
        .best_ask(best_ask),         // FIXED: Connects the lowest sell price
        .busy(book_busy)
    );

    // --- 3. Trading Logic ---
    // Replaces the old temporary TX loopback
    trading_logic TRADING_STRATEGY (
        .clk(clk),
        .reset(reset),
        .best_bid(best_bid),
        .best_ask(best_ask),
        .book_busy(book_busy),
        .tx_data(tx_data),      // Directly feeds UART TX
        .tx_valid(tx_valid)     // Directly triggers UART TX
    );

    // Update LEDs with the parsed Token ID for visual confirmation
    always_ff @(posedge clk) begin
        if (reset) debug_led <= 0;
        else if (parse_valid) debug_led <= token[7:0];
    end

endmodule
