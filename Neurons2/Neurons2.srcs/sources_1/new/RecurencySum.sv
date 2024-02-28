`timescale 1ns / 1ps

module RecurencySum #(
    parameter N = 8,
    parameter R = 8,
    parameter RO = R+$clog2(N+1)
)(
    input logic[N*R-1:0] value_vector,
    output wire[RO-1:0] output_sum
);

    generate
        if (N == 1)
            assign output_sum = value_vector;
        else if (N == 2)
            assign output_sum = value_vector[2*R-1:R] + value_vector[R-1:0];
        else begin            
            localparam LN = N/2;
        
            wire[R+$clog2(LN):0] value_a;
            wire[R+$clog2(N-LN):0] value_b;
            
            RecurencySum #(.N(LN), .R(R)) submodule_a(
                .value_vector(value_vector[R*LN-1:0]), 
                .output_sum(value_a)
            );
            RecurencySum #(.N(N-LN), .R(R)) submodule_b(
                .value_vector(value_vector[R*N-1:R*LN]), 
                .output_sum(value_b)
            );
            
            assign output_sum = value_a + value_b;
        end    
    endgenerate

endmodule
