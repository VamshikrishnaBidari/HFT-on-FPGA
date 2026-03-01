`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 17.02.2026 19:47:16
// Design Name: 
// Module Name: add_order
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

module add_order #(parameter IS_BID = 1) (
    input logic clk,
    input logic reset,
    input logic start,
    input logic valid,       
    input logic price_valid, 
    
    input order_t order,     
    input logic [7:0] price_distr, 
    input logic [7:0] cur_dpt,     
    input logic [23:0] best_price,
    
    output logic [7:0] addr,
    output logic mem_start,
    output order_t data_w,         
    output logic [23:0] price_update,
    output logic [7:0] quantity_update,
    output logic [7:0] quantity_total,
    output logic is_write,
    output logic ready,
    output logic [7:0] dpt_update,
    output logic [23:0] add_best_price
);

    state_t curr_state, nxt_state;
    logic [7:0] addr_nxt, dpt_nxt;
    logic mem_start_nxt, is_write_nxt, ready_nxt;
    logic [23:0] price_update_nxt;
    logic [7:0] quantity_update_nxt, quantity_total_nxt;
    order_t data_w_nxt;
    logic [23:0] add_best_price_nxt;

    always_ff @(posedge clk) begin
        if (reset) begin
            curr_state      <= IDLE;
            addr            <= 0; 
            mem_start <= 0; 
            data_w <= 0; 
            is_write        <= 0; 
            price_update <= 0; 
            quantity_update <= 0;
            quantity_total  <= 0; 
            ready <= 0; 
            dpt_update <= 0; 
            add_best_price <= 0;
        end else begin
            curr_state      <= nxt_state;
            addr            <= addr_nxt; 
            mem_start <= mem_start_nxt; 
            data_w <= data_w_nxt;
            is_write        <= is_write_nxt; 
            ready <= ready_nxt; 
            dpt_update <= dpt_nxt;
            add_best_price  <= add_best_price_nxt; 
            price_update <= price_update_nxt;
            quantity_update <= quantity_update_nxt; 
            quantity_total <= quantity_total_nxt;
        end
    end

    always_comb begin
        nxt_state = curr_state; addr_nxt = addr; mem_start_nxt = mem_start;
        data_w_nxt = data_w; ready_nxt = 1'b0; is_write_nxt = 0; dpt_nxt = cur_dpt;
        add_best_price_nxt = add_best_price; price_update_nxt = price_update;
        quantity_update_nxt = quantity_update; quantity_total_nxt = quantity_total;

        case (curr_state)
            IDLE: begin
                ready_nxt = 0;
                if (start && cur_dpt < 255) begin 
                    nxt_state = WRITE_MEM;
                    addr_nxt = cur_dpt; 
                    mem_start_nxt = 1; is_write_nxt = 1; data_w_nxt = order; 
                    dpt_nxt = cur_dpt + 1;
                    price_update_nxt = order.price; quantity_update_nxt = order.quantity;
                    quantity_total_nxt = price_distr + order.quantity;

                    // UPDATED: Dynamic Min/Max Check based on Market Side
                    if (!price_valid) begin
                        add_best_price_nxt = order.price;
                    end else if (IS_BID && (order.price > best_price)) begin
                        add_best_price_nxt = order.price; // Bids look for Highest Price
                    end else if (!IS_BID && (order.price < best_price)) begin
                        add_best_price_nxt = order.price; // Asks look for Lowest Price
                    end else begin
                        add_best_price_nxt = best_price;
                    end
                end
            end

            WRITE_MEM: begin
                mem_start_nxt = 0; 
                if (valid) begin
                    ready_nxt = 1;
                    nxt_state = IDLE;
                end
            end
            default: nxt_state = IDLE;
        endcase
    end
endmodule
