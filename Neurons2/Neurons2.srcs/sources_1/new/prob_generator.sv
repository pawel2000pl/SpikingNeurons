`timescale 1ns / 1ps

module prob_generator #(
    parameter R=4
) (
    input logic[R-1:0] value,
    input logic[R-1:0] random,
    output wire out
    );
    
    wire[R:0] middle;
    assign middle[0] = 0;
    
    genvar i;
    generate 
        for (i=0;i<R;i=i+1)
            assign middle[i+1] = value[i] ? middle[i] | random[i] : middle[i] & random[i];  
    endgenerate
    
    assign out = middle[R];
    
endmodule
