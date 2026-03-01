`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.03.2026 12:24:50
// Design Name: 
// Module Name: order_book_half
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
import hft_types::*;

module order_book_half #(parameter IS_BID = 1) (
    input logic clk,
    input logic reset,
    
    input logic new_packet,
    input logic [7:0] msg_type, 
    input order_t parsed_order,
    
    output logic [23:0] best_price, 
    output logic busy
);

    logic [7:0] book_size;
    logic mem_start, mem_we; logic [7:0] mem_addr;
    order_t mem_data_in, mem_data_out; logic mem_valid;

    logic add_start, add_busy, add_mem_start, add_mem_we; logic [7:0] add_mem_addr, add_new_size;
    order_t add_mem_data; logic [23:0] add_best_price;

    logic dec_start, dec_busy, dec_mem_start, dec_mem_we; logic [7:0] dec_mem_addr, dec_new_size;
    order_t dec_mem_data;

    // The BRAM instance (Vivado allows multiple instances of the same IP)
    memory_wrapper MEM_WRAP (
        .clk(clk), .reset(reset), .start(mem_start), .is_write(mem_we),
        .addr(mem_addr), .data_in(mem_data_in), .data_out(mem_data_out), .valid(mem_valid)
    );

    // Add Order (Passes the IS_BID parameter down)
    add_order #(.IS_BID(IS_BID)) ADD_LOGIC (
        .clk(clk), .reset(reset), .start(add_start), .valid(mem_valid), 
        .price_valid(book_size > 0), .order(parsed_order), .price_distr(0), 
        .cur_dpt(book_size), .best_price(best_price), .addr(add_mem_addr),
        .mem_start(add_mem_start), .data_w(add_mem_data), .is_write(add_mem_we),
        .ready(), .dpt_update(add_new_size), .add_best_price(add_best_price)
    );

    // Decrease Order
    decrease_order DEC_LOGIC (
        .clk(clk), .reset(reset), .start(dec_start),
        .target_order_id(parsed_order.order_id), .decrease_qty(parsed_order.quantity),
        .is_cancel_msg(msg_type == 8'h58), .current_book_size(book_size),
        .read_data(mem_data_out), .read_valid(mem_valid), .mem_start(dec_mem_start),
        .mem_write_en(dec_mem_we), .mem_addr(dec_mem_addr), .mem_data_w(dec_mem_data),
        .busy(dec_busy), .new_book_size(dec_new_size)
    );

    typedef enum logic [1:0] {WAIT, ADDING, DECREASING} state_t;
    state_t state;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= WAIT; book_size <= 0; best_price <= (IS_BID ? 0 : 24'hFFFFFF);
            add_start <= 0; dec_start <= 0;
        end else begin
            add_start <= 0; dec_start <= 0;

            case (state)
                WAIT: begin
                    busy <= 0;
                    if (new_packet) begin
                        busy <= 1;
                        if (msg_type == 8'h4E) begin 
                            state <= ADDING; add_start <= 1;
                        end else if (msg_type == 8'h58 || msg_type == 8'h54) begin 
                            state <= DECREASING; dec_start <= 1;
                        end
                    end
                end
                ADDING: begin
                    mem_start <= add_mem_start; mem_we <= add_mem_we;
                    mem_addr <= add_mem_addr; mem_data_in <= add_mem_data;
                    
                    if (!add_mem_start && !add_start) begin 
                       book_size <= add_new_size; best_price <= add_best_price; state <= WAIT;
                    end
                end
                DECREASING: begin
                    mem_start <= dec_mem_start; mem_we <= dec_mem_we;
                    mem_addr <= dec_mem_addr; mem_data_in <= dec_mem_data;
                    
                    if (!dec_busy && !dec_start) begin
                        book_size <= dec_new_size; state <= WAIT;
                    end
                end
            endcase
        end
    end
endmodule