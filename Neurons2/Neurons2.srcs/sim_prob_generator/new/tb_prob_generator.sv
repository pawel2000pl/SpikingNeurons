`timescale 1ns / 1ps

module tb_prob_generator();

    logic[3:0] value;
    logic[3:0] random;
    wire pg_out;
    
    logic clk;
    logic reset;

    prob_generator pg(
        .value(value),
        .random(random),
        .out(pg_out)
    );
    
    prime_random_lite_generator rng(
        .clk(clk),
        .reset(reset),
        .seed(15),
        .value(random)
    );
    
    always
    begin
        #5
        clk <= ~clk;
    end    
    
    integer sum;
    initial
    begin
        clk = 0;
        reset = 1;
        #10
        reset = 0;
        #10
        value = 0;
        
        for (integer i=0;i<16;i=i+1)
        begin      
            value = i;   
            sum = 0;   
            for (integer j=0;j<16*1024;j=j+1)
            begin
                #10
                sum = sum + pg_out;
            end
            $display(value, ": sum: ", sum, " expected: ", i*1024);
        end
    
        $finish;
    end

endmodule
