`timescale 1ns / 1ps

module tb_core_mem();

    logic clk;
    logic reset;
    logic rx;
    logic tx;
        
    always
    begin
        #20
        clk <= ~clk;
    end
    
    
    AIProcessor #(.CLK_FREQ(25000000), .BAUD_RATE(5000000)) ai_processor(
        .clk(clk),
        .reset_async(reset),
        .tx(rx),
        .rx(tx)
    );

    transmitter trans(.tx(tx));
    
    initial             
    begin               
        clk <= 0;       
        reset <= 1;     
        rx <= 1;        
        #200             
        reset <= 0;     
      
    end 
    
endmodule
