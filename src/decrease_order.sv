`timescale 1ns / 1ps
import hft_types::*;

module decrease_order(
    input logic clk,
    input logic reset,
    
    // Inputs from Parser
    input logic start,
    input logic [15:0] target_order_id,
    input logic [15:0] decrease_qty, // If 0, it means DELETE completely (Cancel)
    input logic is_cancel_msg,       // 1 = Cancel Msg (Delete), 0 = Trade Msg (Reduce Qty)
    
    // Memory Interface (read results)
    input logic [7:0] current_book_size,
    input order_t read_data,
    input logic read_valid,
    
    // Outputs to Memory Wrapper
    output logic mem_start,
    output logic mem_write_en,
    output logic [7:0] mem_addr,
    output order_t mem_data_w,
    
    // Status Outputs
    output logic busy,
    output logic [7:0] new_book_size
);

    // States
    typedef enum logic [2:0] {IDLE, SEARCH, CHECK_MATCH, SHIFT_READ, SHIFT_WRITE, DONE} state_t;
    state_t state;

    logic [7:0] search_ptr;
    logic [7:0] write_ptr;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            busy <= 0;
            mem_start <= 0;
            mem_write_en <= 0;
            search_ptr <= 0;
            new_book_size <= 0;
        end else begin
            // Defaults
            mem_start <= 0;
            mem_write_en <= 0;

            case (state)
                IDLE: begin
                    busy <= 0;
                    if (start && current_book_size > 0) begin
                        state <= SEARCH;
                        search_ptr <= 0;
                        busy <= 1;
                    end
                end

                SEARCH: begin
                    // Request Read at search_ptr
                    mem_addr <= search_ptr;
                    mem_start <= 1; // Pulse start
                    mem_write_en <= 0;
                    state <= CHECK_MATCH;
                end

                CHECK_MATCH: begin
                    if (read_valid) begin
                        // Check if ID matches
                        if (read_data.order_id == target_order_id) begin
                            // MATCH FOUND
                            // Case 1: Partial execution (Trade) and qty > decrease
                            if (!is_cancel_msg && read_data.quantity > decrease_qty) begin
                                // Update quantity in place
                                mem_addr <= search_ptr;
                                mem_data_w <= read_data; 
                                mem_data_w.quantity <= read_data.quantity - decrease_qty;
                                mem_write_en <= 1;
                                mem_start <= 1;
                                new_book_size <= current_book_size; // Size doesn't change
                                state <= DONE;
                            end else begin
                                // Case 2: Cancel OR Quantity went to 0 -> DELETE
                                // We must shift everything below this up by one
                                write_ptr <= search_ptr; // Start overwriting here
                                search_ptr <= search_ptr + 1; // Read from next
                                state <= SHIFT_READ;
                            end
                        end else begin
                            // No match, keep searching
                            if (search_ptr < current_book_size - 1) begin
                                search_ptr <= search_ptr + 1;
                                state <= SEARCH;
                            end else begin
                                // End of book, ID not found
                                new_book_size <= current_book_size;
                                state <= DONE;
                            end
                        end
                    end
                end

                // Logic to delete an entry by shifting array up
                // mem[write_ptr] = mem[write_ptr + 1]
                SHIFT_READ: begin
                    if (search_ptr < current_book_size) begin
                        mem_addr <= search_ptr; // Read the *next* item
                        mem_start <= 1;
                        mem_write_en <= 0;
                        state <= SHIFT_WRITE;
                    end else begin
                        // Finished shifting
                        new_book_size <= current_book_size - 1;
                        state <= DONE;
                    end
                end

                SHIFT_WRITE: begin
                    if (read_valid) begin
                        mem_addr <= write_ptr; // Write to the *current* slot
                        mem_data_w <= read_data;
                        mem_start <= 1;
                        mem_write_en <= 1;
                        
                        // Increment pointers
                        write_ptr <= write_ptr + 1;
                        search_ptr <= search_ptr + 1;
                        state <= SHIFT_READ;
                    end
                end

                DONE: begin
                    busy <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule