`timescale 1ns / 1ps
import hft_types::*; 

module hft_core (
    input  logic       clk,
    input  logic       reset,
    
    // Interface with UART
    input  logic [7:0] rx_data,
    input  logic       rx_valid,
    output logic [7:0] tx_data,
    output logic       tx_valid,
    
    // Debug
    output logic [7:0] debug_led
);

    // =====================================================================
    // 1. Parser Interconnects
    // =====================================================================
    logic [95:0] packet;
    logic        comp_packet;
    
    logic [7:0]  msg_type, side; 
    logic [3:0]  stock_id, flags;   
    logic [15:0] token, quantity;
    logic [23:0] price;
    logic        parse_valid;

    packet_assembler ASSEMBLER (
        .clk(clk), .reset(reset),
        .uart_byte(rx_data), .rx_data_valid(rx_valid), 
        .packet(packet), .packet_valid(comp_packet)
    );

    parsing PARSER (
        .clk(clk), .reset(reset),
        .packet_in(packet), .packet_valid_in(comp_packet),  
        .msg_type(msg_type), .side(side), .token(token),
        .quantity(quantity), .price(price), .stock_id(stock_id),
        .flags(flags), .parse_valid(parse_valid)
    );

    // =====================================================================
    // 1.5 ORDER ID MAP (Pipeline Stage)
    // =====================================================================
    order_t parsed_order;
    order_t enriched_order;
    logic   enriched_valid;

    assign parsed_order.msg_type = msg_type;
    assign parsed_order.token    = token;
    assign parsed_order.side     = side;
    assign parsed_order.price    = price;
    assign parsed_order.quantity = quantity;
    assign parsed_order.stock_id = stock_id;
    assign parsed_order.flags    = flags; 

    order_id_map GLOBAL_MAP (
        .clk(clk), .reset(reset),
        .parse_valid_in(parse_valid), .parsed_order_in(parsed_order),
        .valid_out(enriched_valid), .enriched_order_out(enriched_order)
    );

    // =====================================================================
    // 1.7 CENTRAL SYNCHRONOUS FIFO (Burst Absorption)
    // =====================================================================
    logic   fifo_empty, central_fifo_full; 
    logic   fifo_rd_en;
    order_t fifo_order;

    sync_fifo #(.WIDTH(80), .DEPTH(512)) CENTRAL_FIFO (
        .clk(clk), .reset(reset),
        .wr_en(enriched_valid), .din(enriched_order), .full(central_fifo_full), 
        .rd_en(fifo_rd_en), .dout(fifo_order), .empty(fifo_empty)
    );

    // =====================================================================
    // 1.8 DEMUX PIPELINE REGISTER (Fixing the -0.564ns WNS)
    // =====================================================================
    order_t     parsed_order_array [0:3];
    logic [3:0] ob_enable;

    // Pipeline registers for execution feed to Trading Logic
    logic        pipe_is_fill;
    logic        pipe_fill_side_val;
    logic [15:0] pipe_fill_qty;
    
    // Active stock tracking to prevent back-to-back overwrite
    logic        pipe_valid;
    logic [3:0]  pipe_target_stock;

    logic [23:0] best_bid     [0:3];
    logic [23:0] best_ask     [0:3]; 
    logic [15:0] best_bid_qty [0:3];
    logic [15:0] best_ask_qty [0:3];
    logic        fifo_full    [0:3]; 

    // FIX: The target order book is busy IF its own busy signal is high, OR
    // if there is currently a packet in this pipeline register headed for it!
    logic active_ob_busy;
    assign active_ob_busy = (fifo_order.stock_id < 4) ? 
                            (fifo_full[fifo_order.stock_id] || (pipe_valid && pipe_target_stock == fifo_order.stock_id)) : 1'b0;

    assign fifo_rd_en = !fifo_empty && !active_ob_busy;

    always_ff @(posedge clk) begin
        if (reset) begin
            for (int j = 0; j < 4; j++) begin
                ob_enable[j]          <= 1'b0;
                parsed_order_array[j] <= '0;
            end
            pipe_is_fill       <= 0;
            pipe_fill_side_val <= 0;
            pipe_fill_qty      <= 0;
            pipe_valid         <= 0;
            pipe_target_stock  <= 0;
        end else begin
            // Default state
            for (int j = 0; j < 4; j++) begin
                ob_enable[j]          <= 1'b0;
                parsed_order_array[j] <= '0;
            end
            pipe_valid   <= 0;
            pipe_is_fill <= 0;

            if (fifo_rd_en && fifo_order.stock_id < 4) begin
                // Route the POPPED FIFO DATA into the fast flip-flops
                ob_enable[fifo_order.stock_id]          <= 1'b1;
                parsed_order_array[fifo_order.stock_id] <= fifo_order;

                pipe_valid        <= 1'b1;
                pipe_target_stock <= fifo_order.stock_id;

                // Pass execution info down the pipeline for the Trading Logic
                pipe_is_fill       <= (fifo_order.msg_type == 8'h54 || fifo_order.msg_type == 8'h45);
                pipe_fill_side_val <= (fifo_order.side == 8'h53) ? 1'b1 : 1'b0;
                pipe_fill_qty      <= fifo_order.quantity;
            end
        end
    end

    // =====================================================================
    // 2. Multi-Stock Routing & Order Books (4 Stocks)
    // =====================================================================
    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : ORDER_BOOK_ARRAY
            order_book_top ORDER_BOOK (
                .clk(clk), .reset(reset),
                .packet_valid(ob_enable[i]), 
                .parsed_order(parsed_order_array[i]), 
                .best_bid(best_bid[i]), .best_bid_qty(best_bid_qty[i]),
                .best_ask(best_ask[i]), .best_ask_qty(best_ask_qty[i]),
                .fifo_full(fifo_full[i])
            );
        end
    endgenerate

    // =====================================================================
    // 3. Output Multiplexer (Tracking the Active Stock)
    // =====================================================================
    logic [1:0] active_stock;
    
    always_ff @(posedge clk) begin
        if (reset) begin
            active_stock <= 2'd0;
        end else if (pipe_valid) begin // Matches pipeline timing perfectly
            active_stock <= pipe_target_stock[1:0];
        end
    end

    logic [23:0] active_best_bid, active_best_ask;
    logic [15:0] active_best_bid_qty, active_best_ask_qty;

    assign active_best_bid     = best_bid[active_stock];
    assign active_best_ask     = best_ask[active_stock];
    assign active_best_bid_qty = best_bid_qty[active_stock];
    assign active_best_ask_qty = best_ask_qty[active_stock];

    // =====================================================================
    // 5. Advanced Market Maker Instantiation
    // =====================================================================
    logic [23:0] final_ask, final_bid;
    logic        final_ask_val, final_bid_val;
    logic [15:0] mm_ask_qty, mm_bid_qty;

    advanced_market_maker #(
        .MAX_POS(500), .MIN_POS(-500)
    ) AMM (
        .clk(clk), .reset(reset),
        .best_bid_valid(active_best_bid > 0),
        .best_ask_valid(active_best_ask > 0 && active_best_ask < 24'hFFFFFF),
        .best_bid(active_best_bid), .best_ask(active_best_ask),
        .best_bid_qty(active_best_bid_qty), .best_ask_qty(active_best_ask_qty),
        
        // Feed the pipelined execution signals
        .fill_valid(pipe_is_fill), .fill_side(pipe_fill_side_val), .fill_qty(pipe_fill_qty), 
        
        .final_ask(final_ask), .final_bid(final_bid),
        .final_ask_val(final_ask_val), .final_bid_val(final_bid_val),
        .final_ask_qty(mm_ask_qty), .final_bid_qty(mm_bid_qty)
    );

    // =====================================================================
    // 6. Order Generation (UART TX Serializer)
    // =====================================================================
    quote_serializer OUTBOUND_ORDERS (
        .clk(clk), .reset(reset),
        .final_ask(final_ask), .final_bid(final_bid),
        .final_ask_val(final_ask_val), .final_bid_val(final_bid_val),
        .stock_id({2'b00, active_stock}), 
        .tx_data(tx_data), .tx_valid(tx_valid),
        .final_ask_qty(mm_ask_qty), .final_bid_qty(mm_bid_qty)
    );

    // =====================================================================
    // 7. Debug LEDs
    // =====================================================================
    always_ff @(posedge clk) begin
        if (reset) debug_led <= 0;
        else if (parse_valid) debug_led <= token[7:0]; 
    end

endmodule