
module clock_divider #(parameter INT_BITS=32, parameter FRAQ_BITS=32) (
    input logic clk,
    input logic[INT_BITS+FRAQ_BITS-1:0] divider,
    output wire out,
    input logic reset
    );
    
    logic[INT_BITS+FRAQ_BITS:0] counter_buf;
    logic out_buf;
    
    wire stage1_comparision;
    assign stage1_comparision = counter_buf[INT_BITS+FRAQ_BITS:FRAQ_BITS] >= divider[INT_BITS+FRAQ_BITS-1:FRAQ_BITS];
    wire[INT_BITS+FRAQ_BITS:0] counter1;
    assign counter1 = counter_buf + (1 << FRAQ_BITS) - (stage1_comparision ? divider : 0);
    wire out_stage_1;
    assign out_stage_1 = out_buf ^ stage1_comparision;
    
    wire stage2_comparision;
    assign stage2_comparision = counter1[INT_BITS+FRAQ_BITS:FRAQ_BITS] >= divider[INT_BITS+FRAQ_BITS-1:FRAQ_BITS];    
    wire out_stage_2;
    assign out_stage_2 = out_stage_1 ^ stage2_comparision;
    wire[INT_BITS+FRAQ_BITS:0] counter2;
    assign counter2 = counter1 + (1 << FRAQ_BITS) - (stage2_comparision ? divider : 0);
    
    always @(posedge clk) counter_buf <= reset ? 0 : counter2;
    always @(posedge clk) out_buf <= reset ? 0 : out_stage_2;
    
    assign out = clk ? out_buf : out_stage_1;

endmodule