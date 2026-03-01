`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: uart_top
// Description: Modified to parse the Token ID to LEDs while simultaneously 
//              echoing the entire 12-byte packet back to the PC using a TX FIFO.
//////////////////////////////////////////////////////////////////////////////////

module uart_top (
    input clk,          // 100MHz Clock (GCLK)
    input reset,        // BTNC
    input rx,           // Pmod JA Pin 3 (from PC)
    output tx,          // Pmod JA Pin 2 (to PC)
    output [7:0] led    // Debug: Shows Token ID
);

    // --- Wires ---
    wire tick;
    wire rx_done_tick;
    wire [7:0] rx_data_out;
    
    // RX FIFO Wires (For Parser)
    wire [7:0] rx_fifo_out;
    wire rx_empty;
    wire fifo_read_en;
    
    // TX FIFO Wires (NEW: For Loopback)
    wire [7:0] tx_fifo_out;
    wire tx_empty;
    wire tx_fifo_not_empty;

    // Parser Wires
    wire [95:0] assembler_packet;
    wire packet_ready;
    wire [15:0] parsed_token;
    wire parse_done;

    // TX Wires
    wire tx_done_tick;

    // 1. Baud Rate Generator (115200 @ 100MHz -> M=54)
    baud_rate_generator #(.M(54), .N(6)) BAUDRATE_GEN (
        .clk(clk), .reset(reset), .tick(tick)
    );

    // 2. UART Receiver
    uart_receiver RX_UNIT (
        .clk(clk), .reset(reset), .rx(rx), .sample_tick(tick),
        .data_ready(rx_done_tick), .data_out(rx_data_out)
    );

    // 3. RX FIFO (Auto-read to Assembler)
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

    // 4. TX FIFO (NEW: Buffers RX data and sends it directly to TX for loopback)
    // ADDR_SPACE_EXP=4 creates a 16-byte deep FIFO, safely holding the 12-byte burst
    assign tx_fifo_not_empty = ~tx_empty;

    fifo #(.DATA_SIZE(8), .ADDR_SPACE_EXP(4)) TX_FIFO (
        .clk(clk), .reset(reset),
        .write_to_fifo(rx_done_tick),   // Write every byte received into TX FIFO
        .read_from_fifo(tx_done_tick),  // Read next byte when transmitter finishes
        .write_data_in(rx_data_out),    // Data directly from Receiver
        .read_data_out(tx_fifo_out),
        .empty(tx_empty),
        .full()
    );

    // 5. Packet Assembler
    packet_assembler ASSEMBLER (
        .clk(clk), .reset(reset),
        .uart_byte(rx_fifo_out),
        .rx_data_valid(fifo_read_en), 
        .packet(assembler_packet),
        .packet_valid(packet_ready)
    );

    // 6. Parser
    parsing PARSER (
        .clk(clk), .reset(reset),
        .packet_in(assembler_packet),
        .packet_valid_in(packet_ready),
        .token(parsed_token),
        .price(), .msg_type(), .side(), .quantity(), // Unused for echo
        .parse_valid(parse_done)
    );

    // 7. Debug LEDs (Visual Check)
    reg [7:0] debug_led;
    always @(posedge clk) begin
        if (reset) debug_led <= 0;
        else if (parse_done) debug_led <= parsed_token[7:0];
    end
    assign led = debug_led;

    // 8. UART Transmitter (Modified for Loopback)
    uart_transmitter TX_UNIT (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_fifo_not_empty),  // Trigger TX whenever TX FIFO has data
        .sample_tick(tick),            // Reuse same baud tick
        .data_in(tx_fifo_out),         // Send the byte waiting in TX FIFO
        .tx_done(tx_done_tick),        // Tells TX FIFO to advance to the next byte
        .tx(tx)
    );

endmodule