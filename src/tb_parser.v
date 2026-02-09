`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.02.2026 15:37:56
// Design Name: 
// Module Name: tb_parser
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


module tb_parser;

    // 1. Inputs/Outputs
    reg clk;
    reg reset;
    reg rx;
    wire tx;
    wire [7:0] leds; // Watch this! It shows the parsed Token ID.

    // 2. Instantiate UUT (Your updated uart_top)
    uart_top uut (
        .clk(clk), 
        .reset(reset), 
        .rx(rx), 
        .tx(tx), 
        .led(leds)
    );

    // 3. Clock Generation (100MHz)
    always #5 clk = ~clk; 

    // 4. Constants
    localparam BIT_PERIOD = 8680; // 115200 baud (100MHz / 868)

    // 5. Task: Send Single Byte (Physical Layer)
    task UART_WRITE_BYTE;
        input [7:0] data;
        integer i;
        begin
            // Start Bit (Low)
            rx = 0; #(BIT_PERIOD); 
            // Data Bits (LSB First)
            for (i=0; i<8; i=i+1) begin
                rx = data[i]; #(BIT_PERIOD);
            end
            // Stop Bit (High)
            rx = 1; #(BIT_PERIOD); 
        end
    endtask

    // 6. Task: Send Full 12-Byte Packet (Protocol Layer)
    task SEND_ORDER_PACKET;
        input [15:0] token_id;
        input [23:0] price;
        begin
            // Byte 0: SOF
            UART_WRITE_BYTE(8'hAA); 
            
            // Byte 1: MsgType 'N' (New Order)
            UART_WRITE_BYTE(8'h4E); 
            
            // Bytes 2-3: Token (Big Endian)
            UART_WRITE_BYTE(token_id[15:8]); 
            UART_WRITE_BYTE(token_id[7:0]); 
            
            // Byte 4: Side (Buy = 'B')
            UART_WRITE_BYTE(8'h42); 
            
            // Bytes 5-7: Price (Big Endian)
            UART_WRITE_BYTE(price[23:16]);
            UART_WRITE_BYTE(price[15:8]);
            UART_WRITE_BYTE(price[7:0]);
            
            // Bytes 8-9: Quantity (10)
            UART_WRITE_BYTE(8'h00);
            UART_WRITE_BYTE(8'h0A);
            
            // Byte 10: Flags (Reserved)
            UART_WRITE_BYTE(8'h00);
            
            // Byte 11: EOF
            UART_WRITE_BYTE(8'h55);
        end
    endtask

    // 7. Main Test Sequence
    initial begin
        clk = 0; reset = 1; rx = 1;
        #100 reset = 0; #100;

        $display("------------------------------------------------");
        $display("Test: Sending Full 12-Byte Order Packet...");
        $display("Packet Info: Token=7, Price=100");
        
        // Send Packet with Token = 7 (0x07) and Price = 100 (0x64)
        SEND_ORDER_PACKET(16'h0007, 24'h000064);
        
        // Wait for serialization (~1.2ms for 12 bytes)
        #1200000; 

        // 8. Verification
        if (leds == 8'h07) 
            $display("[PASS] Parser Logic Verified! LEDs show Token ID: %h", leds);
        else 
            $display("[FAIL] Expected Token 07, Got %h. Check Byte Alignment.", leds);

        $display("------------------------------------------------");
        $finish;
    end

endmodule
