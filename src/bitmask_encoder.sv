`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.03.2026 08:30:41
// Design Name: 
// Module Name: bitmask_encoder
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


module bitmask_encoder #(
    parameter IS_BID = 1 
)(
    input  logic [255:0] mask,
    input  logic [7:0]   limit_index,  // Index of the 4th best price currently in Top-K cache
    output logic [7:0]   best_index,
    output logic         valid
);

    always_comb begin
        best_index = 8'd0;
        valid      = 1'b0;

        // Vivado will unroll these loops into a highly optimized parallel priority tree.
        if (IS_BID) begin
            // BID: We want the highest price (highest index) that is strictly WORSE (lower) than limit_index.
            for (int i = 255; i >= 0; i--) begin
                if (mask[i] && (i < limit_index)) begin
                    best_index = i[7:0];
                    valid      = 1'b1;
                    break;
                end
            end
        end else begin
            // ASK: We want the lowest price (lowest index) that is strictly WORSE (higher) than limit_index.
            for (int i = 0; i <= 255; i++) begin
                if (mask[i] && (i > limit_index)) begin
                    best_index = i[7:0];
                    valid      = 1'b1;
                    break;
                end
            end
        end
    end

endmodule
