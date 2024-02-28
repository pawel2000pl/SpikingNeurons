/*
from sympy import nextprime, is_primitive_root
from random import randint

def generate_value(n_bits):
    p = randint(2**n_bits-1, 2**(n_bits+1)-1)
    while (p:=nextprime(p)):
        if is_primitive_root(2, p):
            return hex(p)
*/            

module prime_random_lite_generator 
    #(parameter divider=65'h13ebc5743cfdddf35, parameter N=$clog2(divider))
    (
        input logic reset,
        input logic[N:0] seed,
        input logic clk,
        output logic[N-1:0] value
    );
    
    logic [N:0] divident;
    
    always @(posedge clk)
    begin
        if (reset)
        begin
            divident <= seed;
            value <= 0;
        end else begin
            divident <= (((divident >= divider) ? (divident - divider) : divident) << 1) | 1;
            value <= divident[N:1];
        end
    end
    
endmodule
