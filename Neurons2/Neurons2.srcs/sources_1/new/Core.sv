`timescale 1ns / 1ps

module Core #(
    parameter N=16,
    parameter R=4,
    parameter RM=$clog2(N+1)+R,
    parameter WORD_SIZE = 32,
    parameter WEIGHT_PER_NEURON = N+3,
    parameter WEIGHT_COUNT = N*WEIGHT_PER_NEURON,
    parameter WEIGHT_STATE_WORDS = (WEIGHT_COUNT*R+WORD_SIZE-1)/WORD_SIZE,
    parameter SWITCHES_WORDS = (3*N*N+WORD_SIZE-1)/WORD_SIZE,
    parameter MASK_WORDS = (N+WORD_SIZE-1)/WORD_SIZE,
    parameter BUF_SIZE = WEIGHT_STATE_WORDS+SWITCHES_WORDS+MASK_WORDS,
    parameter BUF_ADDR_SIZE = $clog2(BUF_SIZE)
) (
    input logic clk,
    input logic reset,
    input logic neuron_reset,
    input logic[BUF_ADDR_SIZE-1:0] mem_addr,
    input logic[WORD_SIZE-1:0] mem_in_value,
    output logic[WORD_SIZE-1:0] mem_out_value,
    output logic[BUF_ADDR_SIZE-1:0] mem_ack_addr,
    input logic we,
    input logic[N-1:0] inputs,
    output wire[N-1:0] outputs,
    
    input logic modify,
    output logic modifying,
    input logic modify_direction,
    input logic[WORD_SIZE-1:0] modify_prob,
    input logic[WORD_SIZE-1:0] modify_seed   
);

    logic[BUF_SIZE-1:0][WORD_SIZE-1:0] buffer;
    wire[WORD_SIZE-1:0] buffer_read;
    assign buffer_read = buffer[mem_addr];
    
    wire[WORD_SIZE*WEIGHT_STATE_WORDS-1:0] weight_buf_bits;
    wire[WORD_SIZE*SWITCHES_WORDS-1:0] switches_bits;    
    
    logic[3:0] prand_reset;
    
    wire[WORD_SIZE:0] random_value;
    wire random_bit;
    prime_random_lite_generator #(.divider(65'h1e348d497c2023973)) prand(
        .clk(clk),
        .reset(prand_reset[3] ^ reset),
        .seed({65'b0, modify_seed}),
        .value(random_value)
    );
    assign random_bit = modify_prob >= random_value[WORD_SIZE-1:0];
    assign sign_bit = random_value[WORD_SIZE] ^ modify_direction;
    
    wire[R-1:0] natural_random;
    ParaNaturalDistributor #(.R(R), .N_LOG_2(4)) pnd(
        .clk(clk),
        .reset(prand_reset[3] ^ reset),
        .seed({65'b0, modify_seed}),
        .value(natural_random)
    );
    wire[R-1:0] modificated_weight = weight_buf_bits[R-1:0];
    wire can_add = random_bit & ~sign_bit & ~&modificated_weight;
    wire can_subb = random_bit & sign_bit & |modificated_weight;
    wire[R-1:0] modified_weight = can_add ? modificated_weight + 1 : can_subb ? modificated_weight - 1 : modificated_weight;
    logic[WORD_SIZE-1:0] modify_counter;
    
    always @(posedge clk)
    begin
        if (reset)
        begin
            buffer <= 0;
            modifying <= 0;       
            prand_reset <= 0;
            modify_counter <= 0;
        end else if (modifying) 
        begin  
            if (prand_reset)         
                prand_reset <= prand_reset >> 1;
            else begin             
                buffer[WEIGHT_STATE_WORDS-1:0] <= {
                    {(WEIGHT_STATE_WORDS*WORD_SIZE-R*WEIGHT_COUNT){1'b0}}, 
                    modified_weight, 
                    weight_buf_bits[R*WEIGHT_COUNT-1:R]
                };
                if (modify_counter == WEIGHT_COUNT-1)
                    modifying <= 0;
                else 
                    modify_counter <= modify_counter + 1;                       
            end        
        end else if (modify) 
        begin
           modifying <= 1;
           prand_reset <= 4'b1000;
            modify_counter <= 0;
        end else begin
            if (mem_addr < BUF_SIZE)
            begin
                mem_out_value <= buffer[mem_addr];
                mem_ack_addr <= mem_addr;
                if (we)
                    buffer[mem_addr] <= mem_in_value;
            end
        end
    end
    
    wire[N-1:0][WEIGHT_PER_NEURON-1:0][R-1:0] weights;
    wire[N-1:0][N-1:0][2:0] switches;
    wire[N-1:0][N-1:0] switches_inputs;    
    wire[WORD_SIZE*MASK_WORDS-1:0] output_mask;
    
    // przełączanie słów pamięci na dane
    genvar i, j, k;
    generate
        for (i=0;i<WEIGHT_STATE_WORDS;i=i+1) 
            assign weight_buf_bits[WORD_SIZE*(i+1)-1:WORD_SIZE*i] = buffer[i];
        for (i=0;i<SWITCHES_WORDS;i=i+1)             
            assign switches_bits[WORD_SIZE*(i+1)-1:WORD_SIZE*i] = buffer[i+WEIGHT_STATE_WORDS];
        for (i=0;i<MASK_WORDS;i=i+1)          
            assign output_mask[WORD_SIZE*(i+1)-1:WORD_SIZE*i] = buffer[i+WEIGHT_STATE_WORDS+SWITCHES_WORDS];             
            
        for (i=0;i<N;i=i+1)
        begin
            for (j=0;j<WEIGHT_PER_NEURON;j=j+1)
                for (k=0;k<R;k=k+1)                
                    assign weights[i][j][k] = weight_buf_bits[R*(WEIGHT_PER_NEURON*i+j)+k];
            for (j=0;j<N;j=j+1)
                assign switches[i][j] = switches_bits[3*(N*i+j)+2:3*(N*i+j)];
        end
    endgenerate
        
    logic[N-1:0][N-1:0] in_values;
    wire[N-1:0] out_values;
    assign outputs = out_values & output_mask[N-1:0];
   
    // neurony

    generate
        for (i=0;i<N;i=i+1)
        begin
            wire[R-1:0] leak;
            assign leak = weights[i][N];
            wire[R-1:0] refraction_time;
            assign refraction_time = weights[i][N+1];
            wire[R-1:0] trigger;
            assign trigger = weights[i][N+2];
            Neuron #(.N(N), .R(R), .RM(RM)) neuron(
                .clk(clk),
                .reset(reset | neuron_reset | modifying),
                .in_value(in_values[i]),
                .out(out_values[i]),
                .weights(weights[i][N-1:0]),
                .leak(leak),
                .refraction_time(refraction_time),
                .trigger(trigger)
            );
        end
    endgenerate

    // macierz połączeń
    generate
        for (i=0;i<N;i=i+1)
            for (j=0;j<N;j=j+1)
                always @(posedge clk, posedge reset) 
                    in_values[i][j] <= reset ? 1'b0 : (switches[i][j][0] ^ ((switches[i][j][1] & out_values[j]) | (switches[i][j][2] & inputs[j])));
    endgenerate

endmodule
