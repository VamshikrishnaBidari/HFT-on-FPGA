`timescale 1ns / 1ps

module order_id_map (
    input  logic        clk,
    
    // Write Interface (Used during Add Order)
    input  logic        we,          
    input  logic [15:0] wr_order_id, 
    input  logic [23:0] wr_price,    
    input  logic [15:0] wr_qty,      
    
    // Read Interface (Used during Cancel/Execute)
    input  logic [15:0] rd_order_id, 
    output logic [23:0] rd_price,   
    output logic [15:0] rd_qty       
);

    // BRAM Inference: 65,536 depth x 40-bit width
    // 16-bit Order ID perfectly maps to 64K addresses.
    // 24-bit price + 16-bit quantity = 40 bits of data.
    (* ram_style = "block" *) logic [39:0] kv_store_bram [0:65535];

    always_ff @(posedge clk) begin
        if (we) begin
            kv_store_bram[wr_order_id] <= {wr_price, wr_qty};
        end
        
        // Synchronous Read: Price and Qty are available 1 clock cycle after rd_order_id is set
        {rd_price, rd_qty} <= kv_store_bram[rd_order_id];
    end

endmodule