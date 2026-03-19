`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.03.2026 08:32:54
// Design Name: 
// Module Name: sync_fifo
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


module sync_fifo #(
    parameter WIDTH = 80, // Struct width
    parameter DEPTH = 512 // Burst absorption size
)(
    input  logic             clk,
    input  logic             reset,
    
    // Write Interface (From Parser)
    input  logic             wr_en,
    input  logic [WIDTH-1:0] din,
    output logic             full,
    
    // Read Interface (To Order Book)
    input  logic             rd_en,
    output logic [WIDTH-1:0] dout,
    output logic             empty
);

    // Distributed or Block RAM inference
     (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];
    
    // Pointers 
    // We add an extra bit to the pointers to easily calculate full/empty states
    logic [$clog2(DEPTH):0] wr_ptr, rd_ptr;

    assign full  = (wr_ptr[$clog2(DEPTH)] != rd_ptr[$clog2(DEPTH)]) && 
                   (wr_ptr[$clog2(DEPTH)-1:0] == rd_ptr[$clog2(DEPTH)-1:0]);
    assign empty = (wr_ptr == rd_ptr);

    // Write Logic
    always_ff @(posedge clk) begin
        if (reset) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr[$clog2(DEPTH)-1:0]] <= din;
            wr_ptr <= wr_ptr + 1;
        end
    end

    // Read Logic
    always_ff @(posedge clk) begin
        if (reset) begin
            rd_ptr <= 0;
            dout   <= 0;
        end else if (rd_en && !empty) begin
            dout   <= mem[rd_ptr[$clog2(DEPTH)-1:0]];
            rd_ptr <= rd_ptr + 1;
        end
    end

endmodule
