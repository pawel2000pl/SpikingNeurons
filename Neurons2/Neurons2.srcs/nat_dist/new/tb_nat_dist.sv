`timescale 1ns / 1ps

module tb_nat_dist();

    logic clk;
    logic reset;
    wire[7:0] value;
    
    ParaNaturalDistributor #(.R(8)) pnd (
        .clk(clk),
        .reset(reset),
        .seed(0),
        .value(value)
    );
    
    always
    begin
        #5
        clk <= ~clk;
        #5
        clk <= ~clk;
        $display($signed(value), ",");
    end    
    
    initial
    begin
        clk = 0;
        reset = 1;
        #10
        reset = 0;
        
        #10000
        $finish;
    end

endmodule
