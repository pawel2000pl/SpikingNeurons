`timescale 1ns / 1ps

module main(
    input logic CLK1,
    input logic sw_in[0:0],
    input logic CONN0[0:0],
    output logic CONN1[0:0],
    output logic LED[7:0],
    output wire LEDR,
    output wire LEDG,
    output wire LEDB
);

    always @(posedge CLK1) LED[0] <= ~CONN0[0];
    always @(posedge CLK1) LED[1] <= ~CONN1[0];
    
    logic reset_prev;
    logic reset;
    always @(posedge CLK1) reset <= sw_in[0];
    always @(posedge CLK1) reset_prev <= reset;
    
    wire clk_4;
    wire clk_div_locked;
    clk_div_4 clk_25MHz (
        .clk_in1(CLK1),
        .clk_out1(clk_4),
        .reset(reset & ~reset_prev),
        .locked(clk_div_locked)
    );

    AIProcessor #(.CLK_FREQ(25000000)) ai_processor(
        .clk(clk_4 & clk_div_locked),
        .reset_async(reset),
        .tx(CONN1[0]),
        .rx(CONN0[0]),
        .byte_recieved(LED[2]),
        .frame_recieved(LED[3])
    );
    
    assign LEDR = 1;
    assign LEDG = 0;
    assign LEDB = 1;
    
endmodule
