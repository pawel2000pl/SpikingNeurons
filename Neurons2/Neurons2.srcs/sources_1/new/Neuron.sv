`timescale 1ns / 1ps

module Neuron #(
    parameter N=1, // liczba synaps
    parameter R=4, // rozdzielczość synaps (wag)
    parameter RM=$clog2(N+1)+R // rozdzielczość licznika
) (
    input logic clk,
    input logic reset,
    input logic[N-1:0] in_value,
    input logic[N-1:0][R-1:0] weights,
    input logic[R-1:0] leak,
    input logic[R-1:0] refraction_time,
    input logic[R-1:0] trigger,
    output logic out
);
    
    wire[N*R-1:0] synapse_inputs;
    wire[RM-1:0] synapse_sum;
    wire[RM-1:0] input_sum;
    
    logic[RM-1:0] value;
    logic refraction;
    
    wire[RM-1:0] new_value;
    
    genvar i;
    generate 
        for (i=0;i<N;i=i+1) 
            assign synapse_inputs[R*(i+1)-1:R*i] = in_value[i] ? weights[i] : 0;
    endgenerate
    
    RecurencySum #(.N(N), .R(R)) rs(
        .value_vector(synapse_inputs), 
        .output_sum(synapse_sum)
    );
    
    assign input_sum = synapse_sum + value;
    
    assign new_value = (input_sum > leak) ? input_sum - leak : 0;
    logic out_buf;
    always @(posedge clk) out <= out_buf;
    
    wire fire;
    assign fire = new_value >= (trigger << (RM-R-1));
    
    always @(posedge clk, posedge reset) 
    begin
        if (reset)
        begin
            refraction <= 0;
            value <= 0;
            out_buf <= 0;
        end else begin
            if (refraction)
            begin
                if (|value)
                    value <= value - 1;
                else
                    refraction <= 0;
                out_buf <= 0;
            end else begin
                value <= fire ? refraction_time : new_value;                
                refraction <= fire;
                out_buf <= fire;
            end
        end
    end

endmodule
