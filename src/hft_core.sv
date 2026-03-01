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
    
    logic [7:0] msg_type, side, flags;
    logic [15:0] token, quantity;
    logic [23:0] price;
    logic parse_valid;

    // Instantiate Assembler
    packet_assembler ASSEMBLER (
        .clk(clk), .reset(reset),
        .uart_byte(rx_data),
        .rx_valid(rx_valid), 
        .packet(packet),
        .comp_packet(comp_packet)
    );

    // Instantiate Parser
    parsing PARSER (
        .clk(clk), .reset(reset),
        .packet(packet),
        .comp_packet(comp_packet),
        .msg_type(msg_type),
        .side(side),
        .flags(flags),
        .token(token),
        .quantity(quantity),
        .price(price),
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

    // --- 3. Output/Response Logic ---
    // We want to send the new Best Bid price back to the PC *after* the order book finishes writing to BRAM.
    logic book_busy_q;
    
    always_ff @(posedge clk) begin
        if (reset) book_busy_q <= 0;
        else book_busy_q <= book_busy;
    end
    
    // Falling Edge Detector: Triggers exactly ONE clock cycle after the order book finishes its operations
    assign tx_valid = (book_busy_q && !book_busy);
    assign tx_data  = best_bid[7:0]; // Send the lower 8 bits of the new best bid back to the PC
    
    // Update LEDs with the parsed Token ID for visual confirmation
    always_ff @(posedge clk) begin
        if (reset) debug_led <= 0;
        else if (parse_valid) debug_led <= token[7:0];
    end

endmodule
