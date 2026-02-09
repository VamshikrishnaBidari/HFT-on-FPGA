`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.02.2026 10:49:05
// Design Name: 
// Module Name: uart_test
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

module uart_test;

    // 1. Inputs/Outputs
    reg clk;
    reg reset;
    reg rx;
    wire tx;
    wire [7:0] leds;

    // 2. Instantiate UUT
    uart_top uut (
        .clk(clk), 
        .reset(reset), 
        .rx(rx), 
        .tx(tx), 
        .led(leds)
    );

    // 3. Clock (100MHz)
    always #5 clk = ~clk; 

    // 4. Constants
    localparam BIT_PERIOD = 8680; // 115200 baud

    // 5. Task: Send Byte to FPGA
    task UART_WRITE_BYTE;
        input [7:0] data;
        integer i;
        begin
            rx = 0; #(BIT_PERIOD); // Start
            for (i=0; i<8; i=i+1) begin
                rx = data[i]; #(BIT_PERIOD);
            end
            rx = 1; #(BIT_PERIOD); // Stop
        end
    endtask

    // 6. Task: Check Response from FPGA
    // This task waits for the Start Bit on 'tx' and reads the byte
    task CHECK_TX_RESPONSE;
        input [7:0] expected_data;
        reg [7:0] received_data;
        integer i;
        begin
            // Wait for Start Bit (Line drops to 0)
            wait(tx == 0);
            
            // Wait 1.5 bit periods to center on the first data bit
            #(BIT_PERIOD + (BIT_PERIOD/2));
            
            // Sample 8 bits
            for (i=0; i<8; i=i+1) begin
                received_data[i] = tx;
                #(BIT_PERIOD);
            end
            
            // Check Result
            if (received_data == expected_data)
                $display("[PASS] TX Correct. Sent %h, Received Back %h", expected_data - 1, received_data);
            else
                $display("[FAIL] TX Mismatch! Expected %h, Got %h", expected_data, received_data);
        end
    endtask

    // 7. Main Test Sequence
    initial begin
        clk = 0; reset = 1; rx = 1;
        #100 reset = 0; #100;

        // --- TEST CASE 1: Send 0xAA (Expect 0xAB back) ---
        $display("------------------------------------------------");
        $display("Test 1: Sending 0xAA...");
        
        // Use 'fork-join' to run sender and checker in parallel
        fork
            UART_WRITE_BYTE(8'hAA); // Send to FPGA
            CHECK_TX_RESPONSE(8'hAB); // Expect AA + 1 = AB
        join
        
        #50000; // Buffer time between tests

        // --- TEST CASE 2: Send 0x55 (Expect 0x56 back) ---
        $display("------------------------------------------------");
        $display("Test 2: Sending 0x55...");
        
        fork
            UART_WRITE_BYTE(8'h55);
            CHECK_TX_RESPONSE(8'h56); // Expect 55 + 1 = 56
        join

        $display("------------------------------------------------");
        $finish;
    end

endmodule