`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.02.2026 10:49:05
// Design Name: 
// Module Name: uart_top
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

module uart_top (
    input clk,
    input reset,
    input rx,
    output tx,
    output [7:0] led 
);

    // Wires
    wire tick;
    wire rx_done_tick;
    wire [7:0] rx_data_out;
    wire [7:0] rx_fifo_out;
    wire rx_empty;
    wire fifo_read_en;
    
    // Parser Wires
    wire [95:0] assembler_packet;
    wire packet_ready;
    wire [15:0] parsed_token;
    wire [23:0] parsed_price; // Connected but not displayed yet
    wire parse_done;

    // 1. Baud Rate Generator
    baud_rate_generator #(.M(54), .N(6)) BAUDRATE_GEN (
        .clk(clk), .reset(reset), .tick(tick)
    );

    // 2. UART Receiver
    uart_receiver RX_UNIT (
        .clk(clk), .reset(reset), .rx(rx), .sample_tick(tick),
        .data_ready(rx_done_tick), .data_out(rx_data_out)
    );

    // 3. RX FIFO
    // Logic: Read immediately if data exists
    assign fifo_read_en = !rx_empty; 
    
    fifo RX_FIFO (
        .clk(clk), .reset(reset),
        .write_to_fifo(rx_done_tick), 
        .read_from_fifo(fifo_read_en), 
        .write_data_in(rx_data_out),
        .read_data_out(rx_fifo_out),
        .empty(rx_empty),
        .full()
    );

    // CRITICAL FIX 1: Remove the 1-cycle delay register (fifo_valid_d).
    // The FIFO output is valid *in the same cycle* that read_en is asserted.
    // The Assembler will latch it at the next clock edge.
    wire rx_data_valid;
    assign rx_data_valid = fifo_read_en; 

    // 4. Packet Assembler
    packet_assembler ASSEMBLER (
        .clk(clk), .reset(reset),
        .uart_byte(rx_fifo_out),
        .rx_data_valid(rx_data_valid), // Use the direct wire
        .packet(assembler_packet),
        .packet_valid(packet_ready)
    );

    // 5. Parser
    parsing PARSER (
        .clk(clk),
        .reset(reset),
        .packet_in(assembler_packet),
        .packet_valid_in(packet_ready),
        .token(parsed_token),
        .price(parsed_price),
        .msg_type(), .side(), .quantity(), 
        .parse_valid(parse_done)
    );

    // 6. Debug / Verification
    reg [7:0] debug_led;
    always @(posedge clk) begin
        // CRITICAL FIX 2: Add Reset Logic to prevent "xx" output
        if (reset) begin
            debug_led <= 8'h00; 
        end else if (parse_done) begin
            debug_led <= parsed_token[7:0]; // Capture Lower 8 bits of Token
        end
    end
    assign led = debug_led;
    
    assign tx = 1'b1;

endmodule
