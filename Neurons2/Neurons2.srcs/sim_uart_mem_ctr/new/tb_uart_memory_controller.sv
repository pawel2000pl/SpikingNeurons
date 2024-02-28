`timescale 1ns / 1ps

module tb_uart_memory_controller();

    logic clk;
    logic reset;
    logic rx;
    logic[7:0] in_data;
    wire[7:0] out_data;
    logic[7:0] ack_addr;
    wire[7:0] addr;
    wire write;

    uart_memory_controller #(
        .CLK_FREQ(100000000),
        .BAUD_RATE(115200),
        .ADDRESS_SIZE(8),
        .WORD_SIZE(8)
    ) umc(
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .tx(tx),
        .addr(addr),
        .write(write),
        .out_data(out_data),
        .in_data(in_data),
        .ack_addr(ack_addr) 
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
        rx <= 1;    
        in_data <= 0;
        ack_addr <= 0;
        #50
        reset <= 0;     
        #10000  
        reset <= 0;                           
             
        //command: write     
        #8680 rx <= 0; //start bit   
        #8680
        rx <= 0;
        #8680
        rx <= 1;
        #8680
        rx <= 0;
        #8680
        rx <= 1;
        #8680
        rx <= 0;
        #8680
        rx <= 1;
        #8680
        rx <= 0;
        #8680
        rx <= 1;
        #8680 rx <= 1; //stop bit   
        
        //address               
        #8680 rx <= 0; //start bit    
        #8680 
        rx <= 0;
        #8680
        rx <= 0;
        #8680
        rx <= 0;
        #8680
        rx <= 0;
        #8680
        rx <= 0;
        #8680
        rx <= 1;
        #8680
        rx <= 1;
        #8680
        rx <= 1;
        #8680 rx <= 1; //stop bit  
                
        //value     
        #8680 rx <= 0; //start bit     
        #8680  
        rx <= 1;
        #8680
        rx <= 1;
        #8680
        rx <= 1;
        #8680
        rx <= 1;
        #8680
        rx <= 1;
        #8680
        rx <= 0;
        #8680
        rx <= 0;
        #8680
        rx <= 0;
        #8680 rx <= 1; //stop bit  
                              
        //command: control byte          
        #8680 rx <= 0; //start bit 
        #8680
        rx <= 1;
        #8680
        rx <= 0;
        #8680
        rx <= 1;
        #8680
        rx <= 0;
        #8680
        rx <= 1;
        #8680
        rx <= 0;
        #8680
        rx <= 1;     
        #8680
        rx <= 0;
        #8680 rx <= 1; //stop bit  
                
        @(posedge write);
        #100000
        ack_addr <= 8'b11100000;
        in_data <= 8'b10010010;
         
        //fake
        #8680 
        rx <= 0;
        #8680 
        rx <= 1;
        
        
        #1100000
        $finish();
    end  


endmodule
