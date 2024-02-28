`timescale 1ns / 1ps

module bit_counter #(
    parameter N=16,
    parameter SIZE_INT = $clog2(N+1)
    ) (
        input logic[N-1:0] bits,
        output wire[SIZE_INT-1:0] value
    );
    
    generate 
        if (N == 1)
            assign value = bits[0];        
        else if (N == 2)
            assign value = bits[0] + bits[1];
        else begin
            localparam LN = N/2;
        
            wire[$clog2(LN+1)-1:0] value_a;
            wire[$clog2(N-LN+1)-1:0] value_b;
        
            bit_counter #(.N(LN)) counter_a (.bits(bits[LN-1:0]), .value(value_a));
            bit_counter #(.N(N-LN)) counter_b (.bits(bits[N-1:LN]), .value(value_b));
            
            assign value = value_a + value_b;        
        end
    endgenerate
    
endmodule
