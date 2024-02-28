`timescale 1ns / 1ps

module ParaNaturalDistributor # (
    parameter R=4,    
    parameter N_LOG_2=4,
    parameter DIVIDER=65'h1c30b7561de530b4b
)(
    input logic clk,
    input logic reset,
    input logic[$clog2(DIVIDER)-1:0] seed,
    output logic[R-1:0] value
);

    localparam N = 1 << N_LOG_2;
    localparam USAGE_GEN_BITS = $clog2(DIVIDER)-1;
    localparam GENERATORS_COUNT = (N*R+USAGE_GEN_BITS-1) / USAGE_GEN_BITS;
    wire[GENERATORS_COUNT*USAGE_GEN_BITS-1:0] random_stream;
    
    genvar i;
    generate
        for (i=0;i<GENERATORS_COUNT;i=i+1)
        begin
            prime_random_lite_generator rnd(
                .clk(clk),
                .reset(reset),
                .seed({USAGE_GEN_BITS{seed+i}}),
                .value(random_stream[(i+1)*USAGE_GEN_BITS-1:i*USAGE_GEN_BITS])
            );
        end
    endgenerate
    
    wire[R+$clog2(N+1)-1:0] random_sum;
    RecurencySum #(.N(N), .R(R)) rs (
        .value_vector(random_stream[R*N-1:0]),
        .output_sum(random_sum)
    );
    
    always @(posedge clk) value <= (random_sum >> N_LOG_2) + (random_sum[N_LOG_2] ? (1 << (R-1))+1 : (1 << (R-1)));
    
endmodule
