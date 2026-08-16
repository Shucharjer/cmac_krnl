`timescale 1ns / 1ps

module axis_packet_counter #(
    parameter DWIDTH = 512
) (
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF prb_axis, ASSOCIATED_RESET aresetn" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    input wire aclk,
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW, INSERT_VIP 0" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    input wire aresetn,


(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 prb_axis TREADY" *)
    input wire prb_axis_tready,
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 prb_axis TVALID" *)
    input wire prb_axis_tvalid,
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 prb_axis TDATA" *)
    input wire [DWIDTH-1:0] prb_axis_tdata,
(* X_INTERFACE_MODE = "monitor" *)
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME prb_axis, HAS_TLAST 1, HAS_TREADY 1" *)
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 prb_axis TLAST" *)
    input wire prb_axis_tlast,

    output reg [31:0] packet_count
);

always @ (posedge aclk) begin
    if (!aresetn) begin
        packet_count = 32'b0;
    end else begin
        if (prb_axis_tready && prb_axis_tvalid && prb_axis_tlast)
            packet_count = packet_count + 1;
    end
end

endmodule
