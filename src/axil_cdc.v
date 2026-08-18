`timescale 1ns / 1ps
//
// AXI4-Lite clock-domain-crossing bridge (32-bit data/address, no bursts).
//
// Forwards the AW / W / AR channels from the fast domain (ap_clk, 300 MHz) to
// the slow CMAC control domain (ctrl_clk, 100 MHz) and returns the B / R
// channels back. Each channel uses an xpm_cdc_handshake full-handshake
// synchronizer, which maps 1:1 onto AXI-Lite valid/ready:
//     src_send/src_rcv  <->  s_axi_*valid / s_axi_*ready
//     dest_req/dest_ack <->  m_axi_*valid / m_axi_*ready
// AXI-Lite has no bursts and at most one outstanding transfer per channel, so
// a per-channel handshake is sufficient and correct.
//
module axil_cdc (
    // ---- Slave side (fast ap_clk domain) ----
    input           s_axi_aclk,
    input           s_axi_aresetn,
    input           s_axi_awvalid,
    input   [31:0]  s_axi_awaddr,
    output          s_axi_awready,
    input           s_axi_wvalid,
    input   [31:0]  s_axi_wdata,
    input   [3:0]   s_axi_wstrb,
    output          s_axi_wready,
    output          s_axi_bvalid,
    output  [1:0]   s_axi_bresp,
    input           s_axi_bready,
    input           s_axi_arvalid,
    input   [31:0]  s_axi_araddr,
    output          s_axi_arready,
    output          s_axi_rvalid,
    output  [31:0]  s_axi_rdata,
    output  [1:0]   s_axi_rresp,
    input           s_axi_rready,
    // ---- Master side (slow ctrl_clk domain) ----
    input           m_axi_aclk,
    input           m_axi_aresetn,
    output          m_axi_awvalid,
    output  [31:0]  m_axi_awaddr,
    input           m_axi_awready,
    output          m_axi_wvalid,
    output  [31:0]  m_axi_wdata,
    output  [3:0]   m_axi_wstrb,
    input           m_axi_wready,
    input           m_axi_bvalid,
    input   [1:0]   m_axi_bresp,
    output          m_axi_bready,
    output          m_axi_arvalid,
    output  [31:0]  m_axi_araddr,
    input           m_axi_arready,
    input           m_axi_rvalid,
    input   [31:0]  m_axi_rdata,
    input   [1:0]   m_axi_rresp,
    output          m_axi_rready
);

    // ---- Forward: AW channel (addr 32-bit) ----
    xpm_cdc_handshake #(
        .DEST_EXT_HSK (1),
        .DEST_SYNC_FF (4),
        .INIT_SYNC_FF (1),
        .SIM_ASSERT_CHK (0),
        .SRC_SYNC_FF  (4),
        .WIDTH        (32)
    ) aw_cdc (
        .src_clk   (s_axi_aclk),
        .src_in    (s_axi_awaddr),
        .src_send  (s_axi_awvalid),
        .src_rcv   (s_axi_awready),
        .dest_clk  (m_axi_aclk),
        .dest_req  (m_axi_awvalid),
        .dest_ack  (m_axi_awready),
        .dest_out  (m_axi_awaddr)
    );

    // ---- Forward: W channel (data 32 + strb 4) ----
    xpm_cdc_handshake #(
        .DEST_EXT_HSK (1),
        .DEST_SYNC_FF (4),
        .INIT_SYNC_FF (1),
        .SIM_ASSERT_CHK (0),
        .SRC_SYNC_FF  (4),
        .WIDTH        (36)
    ) w_cdc (
        .src_clk   (s_axi_aclk),
        .src_in    ({s_axi_wdata, s_axi_wstrb}),
        .src_send  (s_axi_wvalid),
        .src_rcv   (s_axi_wready),
        .dest_clk  (m_axi_aclk),
        .dest_req  (m_axi_wvalid),
        .dest_ack  (m_axi_wready),
        .dest_out  ({m_axi_wdata, m_axi_wstrb})
    );

    // ---- Backward: B channel (resp 2-bit) ----
    xpm_cdc_handshake #(
        .DEST_EXT_HSK (1),
        .DEST_SYNC_FF (4),
        .INIT_SYNC_FF (1),
        .SIM_ASSERT_CHK (0),
        .SRC_SYNC_FF  (4),
        .WIDTH        (2)
    ) b_cdc (
        .src_clk   (m_axi_aclk),
        .src_in    (m_axi_bresp),
        .src_send  (m_axi_bvalid),
        .src_rcv   (m_axi_bready),
        .dest_clk  (s_axi_aclk),
        .dest_req  (s_axi_bvalid),
        .dest_ack  (s_axi_bready),
        .dest_out  (s_axi_bresp)
    );

    // ---- Forward: AR channel (addr 32-bit) ----
    xpm_cdc_handshake #(
        .DEST_EXT_HSK (1),
        .DEST_SYNC_FF (4),
        .INIT_SYNC_FF (1),
        .SIM_ASSERT_CHK (0),
        .SRC_SYNC_FF  (4),
        .WIDTH        (32)
    ) ar_cdc (
        .src_clk   (s_axi_aclk),
        .src_in    (s_axi_araddr),
        .src_send  (s_axi_arvalid),
        .src_rcv   (s_axi_arready),
        .dest_clk  (m_axi_aclk),
        .dest_req  (m_axi_arvalid),
        .dest_ack  (m_axi_arready),
        .dest_out  (m_axi_araddr)
    );

    // ---- Backward: R channel (data 32 + resp 2) ----
    xpm_cdc_handshake #(
        .DEST_EXT_HSK (1),
        .DEST_SYNC_FF (4),
        .INIT_SYNC_FF (1),
        .SIM_ASSERT_CHK (0),
        .SRC_SYNC_FF  (4),
        .WIDTH        (34)
    ) r_cdc (
        .src_clk   (m_axi_aclk),
        .src_in    ({m_axi_rdata, m_axi_rresp}),
        .src_send  (m_axi_rvalid),
        .src_rcv   (m_axi_rready),
        .dest_clk  (s_axi_aclk),
        .dest_req  (s_axi_rvalid),
        .dest_ack  (s_axi_rready),
        .dest_out  ({s_axi_rdata, s_axi_rresp})
    );

endmodule
