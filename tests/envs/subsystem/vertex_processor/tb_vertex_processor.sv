`ifndef TB_VERTEX_PROCESSOR_SV
`define TB_VERTEX_PROCESSOR_SV

module tb_vertex_processor;
  import uvm_pkg::*;
  import pipe_pkg::*;
  import clk_rst_pkg::*;
  import vertex_processor_env_pkg::*;
  import vertex_processor_seq_pkg::*;
  `include "uvm_macros.svh"

  // Clock & Reset Interface
  clk_rst_if clk_rst_i();

  wire clk   = clk_rst_i.clk;
  wire rst_n = clk_rst_i.rst_n;
  wire reset = ~rst_n; // DUT reset is active high

  // Start/done control channel (TB drives start_i, DUT drives gpu_done_o)
  gpu_hs_if ctrl_if(clk, rst_n);

  // DMA request channel: DUT is source (gpu_valid_o / gpu_address_o),
  // TB responds (dma_ready_i).
  pipe_if #(.DATA_W(32)) dma_req_if(clk, rst_n);
  // DMA response channel: TB is source (dma_valid_i / dma_data_i),
  // DUT accepts (gpu_ready_o).
  pipe_if #(.DATA_W(32)) dma_rsp_if(clk, rst_n);
  // Vertex position output channel: DUT is source (v_fifo_wrreq / vertex_xyzw).
  pipe_if #(.DATA_W(108)) vout_if(clk, rst_n);
  // Vertex normal/shade output channel: DUT is source (vn_fifo_wrreq / shade_vn_o).
  pipe_if #(.DATA_W(27)) vnout_if(clk, rst_n);

  // Instantiate DUT
  vertex_processor dut (
    .clk           (clk),
    .reset         (reset),
    .start_i       (ctrl_if.start),
    .dma_ready_i   (dma_req_if.ready),
    .dma_valid_i   (dma_rsp_if.valid),
    .dma_data_i    (dma_rsp_if.data),
    .gpu_valid_o   (dma_req_if.valid),
    .gpu_address_o (dma_req_if.addr),
    .gpu_done_o    (ctrl_if.done),
    .gpu_ready_o   (dma_rsp_if.ready),
    .vertex_xyzw   (vout_if.data),
    .v_fifo_wrreq  (vout_if.valid),
    .v_fifo_full   (~vout_if.ready),
    .shade_vn_o    (vnout_if.data),
    .vn_fifo_wrreq (vnout_if.valid),
    .vn_fifo_full  (~vnout_if.ready)
  );

  // ---- Debug trace (TEMPORARY, gated): DUT control state + FIFO handshakes, every cycle ----
  // Added for the frame-1 DMA-accept investigation (round 4); the vout-stall
  // deadlock it was for is fixed (SM return_state fix + edge-latched fifo_sink).
  // Gated OFF by default from 2026-09-25: unconditionally on, it dominated the
  // regression logs (~300K lines / 64MB per basic run). Enable per-run with
  // +VP_DBG when debugging — notably the post-fix verification runs for
  // WO-20260924-02 (w_norm) and WO-20260903-04 (vn_shade), where per-cycle
  // w_norm state/used/rdy is the fastest way to see a residual defect. Remove
  // this block once those two DUT WOs are closed.
  bit vp_dbg = 0;
  initial vp_dbg = $test$plusargs("VP_DBG");
  integer dbg_cycle = 0; // 5th-run trace showed cyc=x: an uninit integer stays X
  always @(posedge clk) begin
    dbg_cycle <= dbg_cycle + 1;
    if (vp_dbg)
      $display("%t cyc=%0d | SM=%s/%s timer=%0d/pre=%0d addr=%0d | gv=%b ga=%0d gr=%b gd=%b | dv=%b dd=0x%08h dr=%b | vout=%b/rdy=%b/0x%027h | vnout=%b/rdy=%b/0x%07h | wnorm=%s used=%0d ro=%b xrdy=%b",
      $time, dbg_cycle,
      sm_state_str(dut.sm0.state), sm_state_str(dut.sm0.prev_state),
      dut.sm0.timer_value, dut.sm0.timer_preload, dut.sm0.gpu_address_o,
      dma_req_if.valid, dma_req_if.addr, dma_rsp_if.ready, ctrl_if.done,
      dma_rsp_if.valid, dma_rsp_if.data, dma_req_if.ready,
      vout_if.valid, vout_if.ready, vout_if.data,
      vnout_if.valid, vnout_if.ready, vnout_if.data,
      wnorm_state_str(dut.v_xform_inst.w_norm_inst.state),
      dut.v_xform_inst.w_norm_inst.fifo_used,
      dut.v_xform_inst.w_norm_inst.ready_o,
      dut.v_xform_inst.ready_o);
  end

  // State enums are compared numerically (module-scope typedefs are not
  // nameable portably from here); values follow the declaration order in
  // the DUT's state_e typedefs. sm0 is vertex_processor_sm_v2 (enum at
  // rtl/vertex_processor/vertex_processor.sv:417) — the 13-state enum at
  // :137 belongs to the UNINSTANTIATED legacy vertex_processor_sm module
  // (the round-4 trace decoded sm states with the wrong table; the v2 SM's
  // state 5 is FETCH_VERTEX, not SET_NUMVTX). w_norm's enum is at :1142.
  function string sm_state_str(input logic [3:0] s);
    case (s)
      4'd0:  sm_state_str = "RESET";
      4'd1:  sm_state_str = "IDLE";
      4'd2:  sm_state_str = "F_MATRIX";
      4'd3:  sm_state_str = "F_LIGHT";
      4'd4:  sm_state_str = "F_NUMVTX";
      4'd5:  sm_state_str = "F_VERTEX";
      4'd6:  sm_state_str = "F_NORMAL";
      4'd7:  sm_state_str = "WAIT_DMA";
      4'd8:  sm_state_str = "XXX";
      default: sm_state_str = "??";
    endcase
  endfunction

  function string wnorm_state_str(input logic [2:0] s);
    case (s)
      3'd0: wnorm_state_str = "RST";
      3'd1: wnorm_state_str = "IDLE";
      3'd2: wnorm_state_str = "RUN";
      3'd3: wnorm_state_str = "WAIT";
      3'd4: wnorm_state_str = "EOF";
      3'd5: wnorm_state_str = "XXX";
      default: wnorm_state_str = "??";
    endcase
  endfunction

  initial begin
    uvm_config_db#(virtual pipe_if #(.DATA_W(32)))::set(null, "*.dma_req_agent*", "vif", dma_req_if);
    uvm_config_db#(virtual pipe_if #(.DATA_W(32)))::set(null, "*.dma_rsp_agent*", "vif", dma_rsp_if);
    uvm_config_db#(virtual pipe_if #(.DATA_W(108)))::set(null, "*.vout_agent*", "vif", vout_if);
    uvm_config_db#(virtual pipe_if #(.DATA_W(27)))::set(null, "*.vnout_agent*", "vif", vnout_if);
    uvm_config_db#(virtual clk_rst_if)::set(null, "*", "vif", clk_rst_i);
    uvm_config_db#(virtual gpu_hs_if)::set(null, "uvm_test_top", "vif", ctrl_if);
    run_test();
  end

endmodule

`endif
