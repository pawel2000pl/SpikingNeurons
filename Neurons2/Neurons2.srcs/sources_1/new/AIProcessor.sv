`timescale 1ns / 1ps

module AIProcessor #(
    parameter N=32,
    parameter R=4,
    parameter RM=$clog2(N+1)+R,    
    parameter CLK_FREQ = 100000000,
    parameter BAUD_RATE = 115200,
    parameter WORD_SIZE = 32,
    parameter LEARNING_BITS = 8,
    parameter BATCH_BITS = 11
) (
    input logic clk,
    input logic reset_async,
    output wire tx,
    input logic rx,
    output wire byte_recieved,
    output wire frame_recieved
);
   
    // 8 bitów dla ustawień domyślnych
    localparam CORE_ADDRESS_SIZE = $clog2((N*(N+3)*R+WORD_SIZE-1)/WORD_SIZE + (3*N*N+WORD_SIZE-1)/WORD_SIZE + (N+WORD_SIZE-1)/WORD_SIZE);
    localparam CORE_PADDED_ADDRESS = 1 << CORE_ADDRESS_SIZE; 
    localparam ADDRESS_SIZE = 16;                
    localparam CONFIG_ADDRESS_OFFSET = CORE_PADDED_ADDRESS+2*N;
        
    wire[ADDRESS_SIZE-1:0] wanted_addr;
    wire write_enabled;
    wire[WORD_SIZE-1:0] write_data;

    logic[15:0] reset_buf;
    wire[3:0] mem_resets;
    wire reset;
    assign reset = |mem_resets | |reset_buf;
    always @(posedge clk) reset_buf <= {reset_buf[14:0], reset_async};

    logic neuron_reset;    
    logic[CORE_ADDRESS_SIZE-1:0] core_mem_addr;
    wire[CORE_ADDRESS_SIZE-1:0] core_mem_ack_addr;
    wire[WORD_SIZE-1:0] core_mem_output;
    logic[WORD_SIZE-1:0] core_mem_input;
    logic core_write_enable;
    
    wire[N-1:0] inputs;
    wire[N-1:0] outputs;
    
    logic modify;
    wire core_modifying;
    logic[WORD_SIZE-1:0] modify_prob;
    logic[WORD_SIZE-1:0] modify_seed;
    logic rollback;
    
    Core #(
        .N(N),
        .R(R),
        .RM(RM),
        .WORD_SIZE(WORD_SIZE)
    ) core (
        .clk(clk),
        .reset(reset),
        .neuron_reset(neuron_reset),
        .mem_addr(core_mem_addr),
        .mem_ack_addr(core_mem_ack_addr),
        .mem_in_value(core_mem_input),
        .mem_out_value(core_mem_output),
        .we(core_write_enable),
        .inputs(inputs),
        .outputs(outputs),
        .modify(modify),
        .modifying(core_modifying),
        .modify_direction(rollback),
        .modify_prob(modify_prob),
        .modify_seed(modify_seed)
    );       
    
    wire[(N*WORD_SIZE+63)/64*64-1:0] random_stream;    
    
    logic[N-1:0][WORD_SIZE-1:0] generate_values;
    
    genvar i;
    // generatory pseudolosowe
    generate
        for (i=0;i<(N*WORD_SIZE+63)/64;i=i+1)
        begin
            prime_random_lite_generator rng(
                .clk(clk),
                .reset(reset),
                .seed({65'b0, i+1}),
                .value(random_stream[64*(i+1)-1:64*i])
            );
        end
    endgenerate
    
    // nadajniki
    generate
        for (i=0;i<N;i=i+1)
            assign inputs[i] = generate_values[i] > random_stream[WORD_SIZE*(i+1)-1:WORD_SIZE*i];        
    endgenerate    
    
    // liczniki wyjściowe
    logic out_counter_reset_flag;
    logic out_counter_reset_flag_state;    
    wire out_counter_reset;
    assign out_counter_reset = reset | (out_counter_reset_flag ^ out_counter_reset_flag_state);
    always @(posedge clk) out_counter_reset_flag_state <= out_counter_reset_flag;
    logic[N-1:0][WORD_SIZE-1:0] out_counters;
    logic[WORD_SIZE-1:0] scan_counter;
    logic[WORD_SIZE-1:0] max_scan_counter;
    wire scan_counter_can_run;
    assign scan_counter_can_run = scan_counter < max_scan_counter;
    
    generate        
        for (i=0;i<N;i=i+1)
        begin
            logic output_buf;
            always @(posedge clk) output_buf <= outputs[i];
            always @(posedge clk, posedge out_counter_reset)
            begin
                if (out_counter_reset)
                    out_counters[i] <= 0;
                else if (output_buf & scan_counter_can_run)
                    out_counters[i] <= out_counters[i] + 1;
            end
        end
        
        always @(posedge clk, posedge out_counter_reset) scan_counter <= out_counter_reset ? 0 : scan_counter_can_run ? scan_counter+1 : scan_counter;        
    endgenerate

    
    localparam BATCH_BUFFER_OFFSET = CONFIG_ADDRESS_OFFSET + 32;
    localparam BATCH_BUFFER_INPUT_SIZE = 16384;
    localparam BATCH_BUFFER_OUTPUT_SIZE = 2048;
    
    logic[BATCH_BITS-1:0] batch_buffer_read_address;
    logic[BATCH_BITS-1:0] batch_buffer_size;
    wire[LEARNING_BITS*N-1:0] batch_buffer_read_input_value;
    wire[N-1:0] batch_buffer_read_output_value;
    logic learning_active;
    wire[N-1:0][WORD_SIZE-1:0] resized_batch_buffer_read_input_value;
    wire[N-1:0][LEARNING_BITS-1:0] batch_expected_output;
    

    logic learning_mode; // 0 - with teacher, 1 - without teacher
    logic[LEARNING_BITS-1:0] learning_one;
    wire[N-1:0][2*LEARNING_BITS-1:0] middle_loss_values;
    wire[2*LEARNING_BITS+$clog2(N+1)-1:0] sum_of_loss_value;
    logic[WORD_SIZE-1:0] prev_loss_batch_value;
    logic[WORD_SIZE-1:0] loss_batch_value;
    wire[WORD_SIZE-1:0] new_loss_batch_value = loss_batch_value + sum_of_loss_value;
    wire accept_new_weights = prev_loss_batch_value >= new_loss_batch_value;
    generate
        for (i=0;i<N;i=i+1)
        begin
            wire[LEARNING_BITS-1:0] my_out_counter = out_counters[i][LEARNING_BITS-1:0];
            wire[2*LEARNING_BITS-1:0] my_x = learning_mode ? my_out_counter : ((batch_expected_output[i] > my_out_counter) ? (batch_expected_output[i] - my_out_counter) : (my_out_counter - batch_expected_output[i]));
            wire[2*LEARNING_BITS-1:0] my_x2 = my_x**2;
            assign middle_loss_values[i] = learning_mode ? my_x * learning_one - my_x2 : my_x2;
        end        
    endgenerate
    RecurencySum #(.N(N), .R(2*LEARNING_BITS)) loss_sumator(
        .value_vector(middle_loss_values), 
        .output_sum(sum_of_loss_value)
    );
    
    generate
        for (i=0;i<N;i=i+1)
        begin
            assign batch_expected_output[i] = batch_buffer_read_output_value[i] ? learning_one : 0;
            assign resized_batch_buffer_read_input_value[i] = batch_buffer_read_input_value[LEARNING_BITS*(i+1)-1:LEARNING_BITS*i] << (WORD_SIZE - LEARNING_BITS);
        end
    endgenerate
    
    batch_buffer_input bbi(
        .clka(clk),
        .clkb(clk),
        .addra(wanted_addr-BATCH_BUFFER_OFFSET),
        .dina(write_data),
        .wea(write_enabled && wanted_addr >= BATCH_BUFFER_OFFSET && wanted_addr < BATCH_BUFFER_OFFSET+BATCH_BUFFER_INPUT_SIZE),
        .addrb(batch_buffer_read_address),
        .doutb(batch_buffer_read_input_value),
        .rstb(reset_buf[0]),
        .rsta_busy(mem_resets[0]),
        .rstb_busy(mem_resets[1])
    );
    
    batch_buffer_output bbo(
        .clka(clk),
        .clkb(clk),
        .addra(wanted_addr-(BATCH_BUFFER_OFFSET+BATCH_BUFFER_INPUT_SIZE)),
        .dina(write_data),
        .wea(write_enabled && wanted_addr >= BATCH_BUFFER_OFFSET+BATCH_BUFFER_INPUT_SIZE && wanted_addr < BATCH_BUFFER_OFFSET+BATCH_BUFFER_INPUT_SIZE+BATCH_BUFFER_OUTPUT_SIZE),
        .addrb(batch_buffer_read_address),
        .doutb(batch_buffer_read_output_value),
        .rstb(reset_buf[0]),
        .rsta_busy(mem_resets[2]),
        .rstb_busy(mem_resets[3])
    );        


    // komunikacja
    logic[WORD_SIZE-1:0] readed_data;
    logic[ADDRESS_SIZE-1:0] selected_addr;
    
    uart_memory_controller #(
        .CLK_FREQ(CLK_FREQ),
        .WORD_SIZE(WORD_SIZE),
        .ADDRESS_SIZE(ADDRESS_SIZE),
        .BAUD_RATE(BAUD_RATE)
    ) umc(
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .tx(tx),
        .addr(wanted_addr),
        .write(write_enabled),
        .out_data(write_data),
        .in_data(readed_data),
        .ack_addr(selected_addr),
        .byte_recieved(byte_recieved),
        .frame_recieved(frame_recieved)
    );
    
    
    // logika
    always @(posedge clk)
    begin
        
        if (reset)
        begin
            max_scan_counter <= (1 << LEARNING_BITS) - 1;
            neuron_reset <= 0;
            generate_values <= 0;
            out_counter_reset_flag <= 0;
            learning_mode <= 1;
            learning_active <= 0;
            batch_buffer_read_address <= 0;
            prev_loss_batch_value <= ~0;
            loss_batch_value <= 0;
            modify <= 0;
            modify_prob <= (~0);
            modify_seed <= 1;
            batch_buffer_size <= (1 << BATCH_BITS) - 1; 
            rollback <= 0;
            learning_one <= 1 << (LEARNING_BITS-2);
        end else begin
                
                
            // pamięć rdzenia - poniżej 256 adresów
            if (wanted_addr < core.BUF_SIZE)
            begin
                core_mem_addr <= wanted_addr; 
                core_mem_input <= write_data;
                core_write_enable <= write_enabled;
                if (wanted_addr == {1'b0, core_mem_ack_addr})
                begin
                    readed_data <= core_mem_output;
                    selected_addr <= {1'b0, core_mem_ack_addr};
                end
            end else begin
                
                // nadajniki
                if (wanted_addr >= CORE_PADDED_ADDRESS && wanted_addr < CORE_PADDED_ADDRESS+N)
                begin
                    if (write_enabled)
                        generate_values[wanted_addr-CORE_PADDED_ADDRESS] <= write_data;
                    readed_data <= generate_values[wanted_addr-CORE_PADDED_ADDRESS];
                    selected_addr <= wanted_addr;
                end
                         
                // liczniki - każdy zapis zeruje, odczyt rzeczywisty
                if (wanted_addr >= CORE_PADDED_ADDRESS+N && wanted_addr < CORE_PADDED_ADDRESS+2*N)
                begin
                    if (write_enabled)
                        out_counter_reset_flag <= ~out_counter_reset_flag_state;
                    readed_data <= out_counters[wanted_addr-(CORE_PADDED_ADDRESS+N)];
                    selected_addr <= wanted_addr;
                end
                
                // konfiguracja - same niestandardowe
                
                // bezpośredni dostęp do licznika wyjściowego
                if (wanted_addr == CONFIG_ADDRESS_OFFSET)
                begin
                    if (write_enabled)
                        out_counter_reset_flag <= ~out_counter_reset_flag_state;
                    readed_data <= scan_counter;
                    selected_addr <= wanted_addr;
                end
                
                // maksimum licznika
                if (wanted_addr == CONFIG_ADDRESS_OFFSET+1)
                begin
                    if (write_enabled)
                    begin
                        out_counter_reset_flag <= ~out_counter_reset_flag_state;
                        max_scan_counter <= write_data;
                    end
                    readed_data <= max_scan_counter;
                    selected_addr <= wanted_addr;
                end
                
                // funkcja straty
                if (wanted_addr == CONFIG_ADDRESS_OFFSET+2)
                begin
                    readed_data <= new_loss_batch_value;
                    selected_addr <= wanted_addr;
                end
                
                // włączanie uczenia
                if (wanted_addr == CONFIG_ADDRESS_OFFSET+3)
                begin
                    if (write_enabled)
                    begin
                        if (|write_data)
                        begin
                            learning_active <= 1;
                            batch_buffer_read_address <= 0;
                            loss_batch_value <= 0;
                            max_scan_counter <= (1 << LEARNING_BITS) - 1;
                            out_counter_reset_flag <= ~out_counter_reset_flag_state;
                        end else
                            learning_active <= 0;
                        rollback <= 0;
                    end
                    readed_data <= learning_active;
                    selected_addr <= wanted_addr;
                end
                
                // tryb uczenia
                if (wanted_addr == CONFIG_ADDRESS_OFFSET+4)
                begin
                    if (write_enabled)
                        learning_mode <= |write_data;
                    readed_data <= learning_mode;
                    selected_addr <= wanted_addr;
                end        
                
                // rozmiar batchu
                if (wanted_addr == CONFIG_ADDRESS_OFFSET+5)
                begin
                    if (write_enabled)
                        batch_buffer_size <= write_data;
                    readed_data <= batch_buffer_size;
                    selected_addr <= wanted_addr;
                end          
                
                // wartość funkcji strat (można przywrócić)
                if (wanted_addr == CONFIG_ADDRESS_OFFSET+6)
                begin
                    if (write_enabled)
                        prev_loss_batch_value <= write_data;
                    readed_data <= prev_loss_batch_value;
                    selected_addr <= wanted_addr;
                end       
                
                // prawdopodobieństwo modyfikacji
                if (wanted_addr == CONFIG_ADDRESS_OFFSET+7)
                begin
                    if (write_enabled)
                        modify_prob <= write_data;
                    readed_data <= modify_prob;
                    selected_addr <= wanted_addr;
                end     
                
                // wartość 1 uczenia
                if (wanted_addr == CONFIG_ADDRESS_OFFSET+8)
                begin
                    if (write_enabled)
                        learning_one <= write_data;
                    readed_data <= learning_one;
                    selected_addr <= wanted_addr;
                end                                                             
                
                // bufory batchu - tylko do zapisu
                if (wanted_addr >= BATCH_BUFFER_OFFSET && wanted_addr < BATCH_BUFFER_OFFSET+BATCH_BUFFER_INPUT_SIZE+BATCH_BUFFER_OUTPUT_SIZE)
                begin
                    readed_data <= 0;
                    selected_addr <= wanted_addr;
                end                                       
                                     
            end
                                                           
                        
            // uczenie - tylko jeśli skończyło liczyć
            if (learning_active && !write_enabled && !core_modifying && !out_counter_reset && !scan_counter_can_run && !neuron_reset)
            begin
                // przypadek pierwszy: batch nieskończony - przejdź do następnej próbki
                if (batch_buffer_read_address < batch_buffer_size)
                begin
                    batch_buffer_read_address <= batch_buffer_read_address + 1;
                    loss_batch_value <= new_loss_batch_value;                
                // przypadek drugi: batch skończony - podsumuj
                end else begin
                    // koniec epoki
                    // jest okej, zmiana może być przyjęta, lub zmianę cofnięto
                    if (rollback || accept_new_weights) 
                    begin
                        modify_seed <= random_stream[WORD_SIZE-1:0];
                        if (rollback)
                            modify_prob <= modify_prob - (modify_prob >> 8);
                        else if (~modify_prob[WORD_SIZE-1])
                            modify_prob <= modify_prob + (modify_prob >> 9) - ((modify_prob >> 11) + 1);
                        rollback <= 0;
                        prev_loss_batch_value <= new_loss_batch_value; // nowe minimum - albo lepsze, albo z tych samych wag (rollback)
                    end else // jak nie, to tryb rollback
                        rollback <= 1;
                    if (modify == 0) modify <= 1; // zawsze coś zmieniamy                                     
                        
                    loss_batch_value <= 0;
                    batch_buffer_read_address <= 0;
                end
                
                if (neuron_reset == 0) neuron_reset <= 1;
            end         
                  
            if (modify == 1) modify <= 0;
            if (neuron_reset == 1) 
            begin
                neuron_reset <= 0;
                generate_values <= resized_batch_buffer_read_input_value;
                out_counter_reset_flag <= ~out_counter_reset_flag_state;
            end
        end    
    end
    

endmodule
