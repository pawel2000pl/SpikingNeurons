`timescale 1ns / 1ps


module uart_memory_controller #(
    parameter CLK_FREQ = 100000000,
    parameter BAUD_RATE = 115200,
    parameter ADDRESS_SIZE = 8,
    parameter WORD_SIZE = 32,
    parameter TIMEOUT = 100000,
    parameter ACK_TIMEOUT = 64
)(
    input logic clk,
    input logic reset,
    input logic rx,
    output logic tx,
    output logic[ADDRESS_SIZE-1:0] addr,
    output logic write,
    output logic[WORD_SIZE-1:0] out_data,
    input logic[WORD_SIZE-1:0] in_data,
    input logic[ADDRESS_SIZE-1:0] ack_addr,
    output wire byte_recieved,
    output wire frame_recieved
);

    localparam FRAME_BYTES = (ADDRESS_SIZE+WORD_SIZE+7)/8 + 2;

    localparam UART_DIVIDER_32 = CLK_FREQ / BAUD_RATE;
    localparam UART_DIVIDER_16_24 = CLK_FREQ * 64'h1000000 / BAUD_RATE;
    
    localparam WRITE_COMMAND = 8'b10101010;
    localparam READ_COMMAND = 8'b01010101;
    localparam ACK_COMMAND = 8'b11000110;
    
    logic[$clog2(TIMEOUT+1):0] timeout_counter;
    wire timeout;
    assign timeout = timeout_counter >= TIMEOUT;
    always @(posedge clk) timeout_counter <= (reset | ~rx) ? 0 : timeout ? timeout_counter : timeout_counter+1;
    
    logic[$clog2(ACK_TIMEOUT+1):0] ack_counter;
    logic[FRAME_BYTES*8-1:0] recieved_frame;
    wire[FRAME_BYTES:0][7:0] valid_frame_part;
    genvar i;
    generate
        assign valid_frame_part[0] = 0;
        for (i=0;i<FRAME_BYTES;i=i+1)
            assign valid_frame_part[i+1] = valid_frame_part[i] ^ recieved_frame[8*i+7:8*i];
    endgenerate
    
    //xor po wszystkich bajtach musi być zerem
    //pierwszy może mieć dwie watości: odczyt, zapis
    wire valid_frame;
    assign valid_frame = (recieved_frame[7:0] == WRITE_COMMAND || recieved_frame[7:0] == READ_COMMAND) & ~|valid_frame_part[FRAME_BYTES];
    
    wire[7:0] uart_recieved_byte;
    wire uart_recieved;
    wire should_transmit; //używane później: tutaj do zmian licznika ack
    
     uart_reciever reciever (
        .clk(clk), 
        .reset(reset), 
        .signal(rx), 
        .f_divider(UART_DIVIDER_32), 
        .value(uart_recieved_byte), 
        .eot(uart_recieved)
    );
        
    always @(posedge clk)
    begin
        if (reset)
        begin
            recieved_frame <= 0;
            write <= 0;
            addr <= 0;
            out_data <= 0;
        end else 
        if (uart_recieved) 
        begin        
            recieved_frame <= {uart_recieved_byte, recieved_frame[8*FRAME_BYTES-1:8]};                 
        end else if (valid_frame)
        begin
            write <= recieved_frame[7:0] == WRITE_COMMAND;
            addr <= recieved_frame[ADDRESS_SIZE+7:8];  
            out_data <= recieved_frame[ADDRESS_SIZE+WORD_SIZE+7:ADDRESS_SIZE+8];    
            recieved_frame <= 0; 
        end else begin
            write <= 0;   
            if (timeout)
                recieved_frame <= 0;    
        end       
        
        if (valid_frame) 
            ack_counter <= ACK_TIMEOUT + 1; 
        else if (should_transmit)
            ack_counter <= 0;
        else if (|ack_counter)
            ack_counter <= ack_counter - 1;   
    end
      
    wire uart_ready_to_send;
       
    
    logic[WORD_SIZE-1:0] in_data_buf;
    logic[ADDRESS_SIZE-1:0] ack_addr_buf;
    always @(posedge clk) in_data_buf <= in_data;
    always @(posedge clk) ack_addr_buf <= ack_addr;
       
    wire[FRAME_BYTES*8-1:0] transmit_frame;
    assign transmit_frame[8+ADDRESS_SIZE+WORD_SIZE-1:0] = {in_data_buf, ack_addr_buf, WRITE_COMMAND};
    
    wire[FRAME_BYTES-1:0][7:0] transmit_xor;
    generate
        if (FRAME_BYTES*8-9 >= ADDRESS_SIZE+WORD_SIZE+8)
            assign transmit_frame[FRAME_BYTES*8-9:ADDRESS_SIZE+WORD_SIZE+8] = 0;
        assign transmit_xor[0] = 0;
        for (i=0;i<FRAME_BYTES-1;i=i+1)
            assign transmit_xor[i+1] = transmit_xor[i] ^ transmit_frame[8*i+7:8*i];
    endgenerate    
    assign transmit_frame[FRAME_BYTES*8-1:FRAME_BYTES*8-8] = transmit_xor[FRAME_BYTES-1];
    
    logic[$clog2(FRAME_BYTES+1):0] bytes_to_send;
    logic[FRAME_BYTES-1:0][7:0] transmit_frame_buf;
    logic[7:0] transmit_byte;
    logic uart_bot;
    
    uart_sender sender(
        .clk(clk),
        .reset(reset), 
        .bot(uart_bot),
        .value(transmit_byte),
        .f_divider(UART_DIVIDER_16_24),  
        .signal(tx), 
        .ready(uart_ready_to_send)
    );
    
    logic[ADDRESS_SIZE-1:0] prev_ack_addr;
    logic[WORD_SIZE-1:0] prev_in_data;
    assign should_transmit = (|(prev_ack_addr ^ ack_addr_buf) | |(prev_in_data ^ in_data_buf)) && (ack_addr_buf == addr)  && (|ack_counter);
    
    always @(posedge clk)
    begin
        if (reset)
        begin
            bytes_to_send <= 0;
            transmit_frame_buf <= 0;
            uart_bot <= 0;            
            prev_ack_addr <= 0;
            prev_in_data <= 0;
        end else if (uart_bot)
            uart_bot <= 0;
        else if(|bytes_to_send)
        begin
            if (uart_ready_to_send)
            begin
                transmit_byte <= transmit_frame_buf[0];
                transmit_frame_buf <= transmit_frame_buf >> 8;           
                bytes_to_send <= bytes_to_send - 1;
                uart_bot <= 1;
            end
        end else 
        if (should_transmit || (ack_counter == 1)) 
        begin
            bytes_to_send <= FRAME_BYTES;
            transmit_frame_buf <= transmit_frame;      
            prev_ack_addr <= ack_addr;
            prev_in_data <= in_data;
        end 
    end

    
    assign byte_recieved = uart_recieved;
    assign frame_recieved = valid_frame;

endmodule
