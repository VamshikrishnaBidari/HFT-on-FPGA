`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 17.02.2026 19:43:21
// Design Name: 
// Module Name: hft_types
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

package hft_types;

    // Define the Order structure to fit your 48-bit BRAM width
    // Total Sum must be 48 bits
    typedef struct packed {
        logic [23:0] price;    // 24 bits: Price
        logic [15:0] order_id; // 16 bits: Order ID (Token)
        logic [7:0]  quantity; // 8 bits:  Quantity
    } order_t; // We call this new type 'order_t'

    // Define States using Enum (Readable names instead of 0, 1, 2)
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        WRITE_MEM = 2'b01,
        WAIT_ACK = 2'b10
    } state_t;

endpackage
