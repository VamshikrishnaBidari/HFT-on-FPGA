`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.03.2026 17:52:00
// Design Name: 
// Module Name: quote_serializer
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

module quote_serializer (
    input  logic        clk,
    input  logic        reset,
    
    // Quotes from Advanced Market Maker
    input  logic [23:0] final_ask,
    input  logic [23:0] final_bid,
    input  logic [15:0] final_ask_qty, // NEW: Dynamic Ask Quantity
    input  logic [15:0] final_bid_qty, // NEW: Dynamic Bid Quantity
    input  logic        final_ask_val,
    input  logic        final_bid_val,
    input  logic [3:0]  stock_id,      // Receives 4-bit stock_id from top-level
    
    // Output to UART TX
    output logic [7:0]  tx_data,
    output logic        tx_valid
);

    logic [23:0] prev_ask, prev_bid;
    logic [15:0] latched_ask_qty, latched_bid_qty; // Latches to hold the dynamic qty during TX
    logic [4:0]  tx_state;
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_state <= 0;
            tx_valid <= 0;
            tx_data  <= 0;
            prev_ask <= 0;
            prev_bid <= 0;
            latched_ask_qty <= 0;
            latched_bid_qty <= 0;
        end else begin
            // Trigger transmission if prices change and are valid
            if (tx_state == 0) begin
                tx_valid <= 0;
                if ((final_ask != prev_ask && final_ask_val) || 
                    (final_bid != prev_bid && final_bid_val)) begin
                    
                    prev_ask <= final_ask;
                    prev_bid <= final_bid;
                    
                    // Securely latch the dynamic quantities at the start of transmission
                    latched_ask_qty <= final_ask_qty; 
                    latched_bid_qty <= final_bid_qty; 
                    
                    tx_state <= 1; // Start TX FSM
                end
            end 
            else begin
                tx_valid <= 1;
                // --- BID ORDER PACKET (12 Bytes) ---
                case (tx_state)
                    1:  tx_data <= 8'hAA;                        // SOF
                    2:  tx_data <= 8'h4F;                        // MsgType 'O' (Outbound Order)
                    3:  tx_data <= 8'h00;                        // Token High (0 - Exchange assigns real ID)
                    4:  tx_data <= 8'h00;                        // Token Low 
                    5:  tx_data <= 8'h42;                        // Side 'B' (Buy)
                    6:  tx_data <= final_bid[23:16];             // Price High
                    7:  tx_data <= final_bid[15:8];              // Price Mid
                    8:  tx_data <= final_bid[7:0];               // Price Low
                    9:  tx_data <= latched_bid_qty[15:8];        // Dynamic Qty High
                    10: tx_data <= latched_bid_qty[7:0];         // Dynamic Qty Low
                    11: tx_data <= {stock_id, 4'h0};             // Flags: Pack stock_id into top 4 bits!
                    12: tx_data <= 8'h55;                        // EOF
                    
                // --- ASK ORDER PACKET (12 Bytes) ---
                    13: tx_data <= 8'hAA;                        // SOF
                    14: tx_data <= 8'h4F;                        // MsgType 'O' (Outbound Order)
                    15: tx_data <= 8'h00;                        // Token High
                    16: tx_data <= 8'h00;                        // Token Low
                    17: tx_data <= 8'h53;                        // Side 'S' (Sell)
                    18: tx_data <= final_ask[23:16];             // Price High
                    19: tx_data <= final_ask[15:8];              // Price Mid
                    20: tx_data <= final_ask[7:0];               // Price Low
                    21: tx_data <= latched_ask_qty[15:8];        // Dynamic Qty High
                    22: tx_data <= latched_ask_qty[7:0];         // Dynamic Qty Low
                    23: tx_data <= {stock_id, 4'h0};             // Flags: Pack stock_id into top 4 bits!
                    24: begin tx_data <= 8'h55; tx_state <= 0; end // EOF & Reset FSM
                endcase
                
                if (tx_state != 0 && tx_state != 24)
                    tx_state <= tx_state + 1;
            end
        end
    end
endmodule
