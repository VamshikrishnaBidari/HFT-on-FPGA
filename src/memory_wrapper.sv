`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 17.02.2026 20:07:24
// Design Name: 
// Module Name: memory_wrapper
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
import hft_types::*; // Use our common types

module memory_wrapper (
    input logic clk,
    input logic reset,
    
    // Interface to Logic Modules (Add/Decrease)
    input logic start,              // Start a read or write operation
    input logic is_write,           // 1 = Write, 0 = Read
    input logic [7:0] addr,         // Address (Depth 256)
    input order_t data_in,          // Input data (Structured)
    
    output order_t data_out,        // Output data (Structured)
    output logic valid              // Goes high when Read Data is ready
);

    // Latency Configuration (Standard BRAM is usually 2 cycles)
    localparam BRAM_LATENCY = 2; 

    // Internal Signals
    logic [3:0] latency_count;
    logic bram_enable;
    logic [0:0] bram_we; // Block RAM expects a vector for Write Enable
    logic [47:0] bram_dina, bram_douta;

    // State Machine for Latency Management
    typedef enum logic {MEM_IDLE, MEM_WAIT} mem_state_t;
    mem_state_t state;

    // Cast struct to bits for the BRAM IP
    assign bram_dina = data_in; 
    assign data_out = order_t'(bram_douta); // Cast bits back to struct
    assign bram_we = (is_write && start) ? 1'b1 : 1'b0;
    assign bram_enable = start || (state == MEM_WAIT);

    // -------------------------------------------------------------------------
    // Instantiate the Vivado Block Memory Generator
    // Name must match what you created in IP Catalog (blk_mem_gen_0)
    // -------------------------------------------------------------------------
    blk_mem_gen_0 M0_BRAM (
        .clka(clk),
        .ena(bram_enable),
        .wea(bram_we),      // Write Enable (vector)
        .addra(addr),       // Address
        .dina(bram_dina),   // Data In (48 bits)
        .douta(bram_douta)  // Data Out (48 bits)
    );

    // -------------------------------------------------------------------------
    // Latency Counter Logic (Matches MIT Project Logic)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= MEM_IDLE;
            valid <= 0;
            latency_count <= 0;
        end else begin
            case (state)
                MEM_IDLE: begin
                    valid <= 0;
                    if (start) begin
                        state <= MEM_WAIT;
                        latency_count <= 1;
                    end
                end

                MEM_WAIT: begin
                    if (latency_count < BRAM_LATENCY) begin
                        latency_count <= latency_count + 1;
                    end else begin
                        // Latency met, data is valid now
                        state <= MEM_IDLE;
                        valid <= 1; 
                    end
                end
            endcase
        end
    end

endmodule
