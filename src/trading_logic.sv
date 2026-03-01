`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.03.2026 14:47:43
// Design Name: 
// Module Name: trading_logic
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

module trading_logic (
    input logic clk,
    input logic reset,
    
    // Inputs from Order Book
    input logic [23:0] best_bid,
    input logic [23:0] best_ask,
    input logic book_busy,
    
    // Output to UART TX Interface
    output logic [7:0] tx_data,
    output logic tx_valid
);

    // Hardcoded threshold for our baseline strategy (e.g., 5 ticks)
    localparam logic [23:0] THRESHOLD = 24'd5;

    // Edge detection for book_busy
    logic book_busy_q;
    logic book_done;
    
    always_ff @(posedge clk) begin
        if (reset) book_busy_q <= 0;
        else book_busy_q <= book_busy;
    end
    
    // Triggers exactly one cycle after the order book finishes writing to BRAM
    assign book_done = (book_busy_q && !book_busy);

    // Trade Logic FSM
    always_ff @(posedge clk) begin
        if (reset) begin
            tx_valid <= 0;
            tx_data <= 0;
        end else begin
            tx_valid <= 0; // Default: do not transmit
            
            if (book_done) begin
                // Check if we have valid bids and asks
                // (Assuming best_bid > 0 and best_ask < 24'hFFFFFF means book is not empty)
                if (best_bid > 0 && best_ask < 24'hFFFFFF) begin
                    
                    // The Core Logic: Spread Comparison
                    if ((best_ask - best_bid) <= THRESHOLD) begin
                        // Spread is tight! Generate Trade Signal
                        tx_data <= 8'h54; // ASCII 'T' (0x54) for Trade
                        tx_valid <= 1;
                    end else begin
                        // No trade. Send back the spread size for Python debugging
                        tx_data <= (best_ask - best_bid); 
                        tx_valid <= 1;
                    end
                    
                end
            end
        end
    end
endmodule
