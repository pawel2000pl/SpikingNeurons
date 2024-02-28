
module uart_sender (
    input logic clk, 
    input logic bot,
    input logic[7:0] value,
    input logic[39:0] f_divider,  
    output logic signal, 
    output wire ready, 
    input logic reset);
    
    wire sending;
    logic[9:0] buffer;
    
    assign sending = |buffer;
    assign ready = ~sending;
    logic prev_send_clock_out;
    wire send_clock_out;
    clock_divider #(.INT_BITS(16), .FRAQ_BITS(24)) send_clock(.clk(clk), .divider(f_divider), .out(send_clock_out), .reset(reset));

    always @(posedge clk)
    begin
        if (reset)
        begin
            buffer <= 0;
            signal <= 1;
        end else if (bot && !sending)
        begin            
            buffer <= {1'b1, value, 1'b0};
        end else if (send_clock_out)
        begin
            if (sending & ~prev_send_clock_out)
            begin
                signal <= buffer[0];
                buffer <= buffer >> 1;
            end
        end
        prev_send_clock_out <= send_clock_out;
    end
    
endmodule
