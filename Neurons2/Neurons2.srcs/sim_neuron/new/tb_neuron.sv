`timescale 1ns / 1ps

module tb_neuron();

    logic clk;
    logic reset;
    logic in_value;
    wire out_value;
    logic[3:0] weight;
    logic[3:0] leak;
    logic[3:0] refraction;
    logic[3:0] trigger;
    
     Neuron neuron(
        .clk(clk),
        .reset(reset),
        .in_value(in_value),
        .out(out_value),
        .weights(weight),
        .leak(leak),
        .trigger(trigger),
        .refraction_time(refraction)
    );
    
    always
    begin
        #5
        clk <= ~clk;
    end
    
    initial
    begin
        clk <= 0;
        reset <= 1;   
        weight <= 13;
        leak <= 2;
        refraction <= 5;   
        in_value <= 1;   
        trigger <= 15;
        #20
        reset <= 0;               
                
        #1000
        weight <= 0;
        leak <= 0;
        refraction <= 0;
        
        #1000
        weight <= 12;
        leak <= 11;
        refraction <= 5;
        
        #1000
        weight <= 5;
        leak <= 10;
        refraction <= 5;
                       
        #1000
        weight <= 15;
        leak <= 1;
        refraction <= 15;
                               
        #1000
        weight <= 4;
        leak <= 1;
        refraction <= 3;
                
        #1000
        weight <= 5;
        leak <= 5;
        refraction <= 15;
        
        #1000
        weight <= 15;
        leak <= 1;
        refraction <= 0;
                
        #1000
        weight <= 1;
        leak <= 0;
        refraction <= 15;
        
        #1000
        weight <= 15;
        leak <= 15;
        refraction <= 0;
    
        #1000
        $finish;
    end

endmodule
