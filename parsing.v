`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.02.2026 15:29:16
// Design Name: 
// Module Name: parsing
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

module parsing(
    input clk,
    input reset,                 
    input [95:0] packet_in,
    input packet_valid_in,
    output reg [7:0] msg_type,
    output reg [15:0] token,
    output reg side,
    output reg [23:0] price,
    output reg [15:0] quantity,
    output reg parse_valid
);

    always @(posedge clk) begin
        if (reset) begin          
            msg_type <= 0;
            token <= 0;
            side <= 0;
            price <= 0;
            quantity <= 0;
            parse_valid <= 0;
        end 
        else if (packet_valid_in) begin
            msg_type <= packet_in[87:80];
            token    <= packet_in[79:64];
            side     <= (packet_in[63:56] == 8'h53) ? 1'b1 : 1'b0; 
            price    <= packet_in[55:32];
            quantity <= packet_in[31:16];
            parse_valid <= 1;
        end else begin
            parse_valid <= 0;
        end
    end
endmodule

