`timescale 1ns / 1ps

module uart_reciever (
    input logic clk, 
    input logic signal, 
    input logic[31:0] f_divider, 
    output logic[7:0] value, 
    output logic eot, 
    input logic reset);

    logic recieving;
    logic ready_to_send;
    logic[31:0] clk_counter;
    logic[31:0] next_read;
    logic[4:0] buf_pos;
    logic[8:0] buffer;
    logic prev_signal;
    
    always @(posedge clk)
    begin
        if (reset)
        begin
            buffer <= 0;
            recieving <= 0;
            clk_counter <= 0;
            ready_to_send <= 0;
        end else if (ready_to_send)
        begin
            ready_to_send <= 0;
            value <= buffer[7:0];
            eot <= 1;
            recieving <= 0;
        end else begin
            eot <= 0;
            if (recieving)
            begin
                clk_counter <= clk_counter+1;
                if (clk_counter == next_read)
                begin
                    next_read <= next_read + f_divider;
                    buffer <= (buffer >> 1) | {signal, 8'b0};
                    if (buf_pos == 8)
                    begin
                        buf_pos <= 0;
                        ready_to_send <= 1;
                    end else
                        buf_pos <= buf_pos + 1;
                end else if (prev_signal ^ signal)
                    next_read <= clk_counter + (f_divider >> 1);
            end else if (!signal) begin
                recieving <= 1;
                clk_counter <= 0;
                next_read <= f_divider + (f_divider >> 1);
                buf_pos <= 0;
                buffer <= 0;
                ready_to_send <= 0;
            end;
            prev_signal <= signal;
        end
    end    

endmodule