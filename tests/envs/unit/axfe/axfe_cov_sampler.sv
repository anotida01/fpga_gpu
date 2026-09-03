`ifndef AXFE_COV_SAMPLER_SV
`define AXFE_COV_SAMPLER_SV

// Functional coverage for the AXFE CTRL AXI-Lite path. A passive analysis-port
// subscriber on axi4lite_seq_item (the same stream the scoreboard consumes),
// so it samples at exactly the monitor's instants with no extra clocking skew.
// It is a REPORTER, not an assertor: a 0% bin is a coverage gap (visible in
// the report), never a test failure. Protocol-level dimensions only (AXI4-Lite
// fields); no DUT-internal signals.
class axfe_cov_sampler extends uvm_subscriber #(axi4lite_seq_item);
  `uvm_component_utils(axfe_cov_sampler)

  // Per-sample scalars consumed by the coverpoints.
  int           op;         // 0 = READ, 1 = WRITE (axi4lite_pkg::op_type_e)
  logic [2:0]   reg_idx;    // addr[4:2] -> 0..4 for Reg0..Reg4 (in-range only)
  logic [1:0]   resp;       // DUT response: 00 OKAY, 01 SLVERR, 10 DECERR, 11 reserved
  logic [3:0]   strb;       // WSTRB (meaningful on writes)
  logic [2:0]   prot;       // AXI4-Lite protection field
  bit           in_range;   // addr[4:0] <= 5'h10 (5-register CTRL map)
  bit           is_write;   // op == WRITE (strb is only meaningful here)

  covergroup cg_axfe_access;
    cp_op   : coverpoint op {
      bins read    = {0};
      bins write   = {1};
    }
    cp_reg  : coverpoint reg_idx iff (in_range) {
      bins reg0 = {0};
      bins reg1 = {1};
      bins reg2 = {2};
      bins reg3 = {3};
      bins reg4 = {4};
    }
    cp_resp : coverpoint resp {
      bins okay     = {2'b00};
      bins slverr   = {2'b01};
      bins decerr   = {2'b10};
      bins reserved = {2'b11};
    }
    cp_strb : coverpoint strb iff (is_write) {
      bins full    = {4'hF};
      bins partial = {[4'h0:4'HE]};
    }
    cp_prot : coverpoint prot {
      bins prot0 = {3'b000};
      bins prot1 = {3'b001};
      bins prot2 = {3'b010};
      bins prot3 = {3'b011};
      bins prot4 = {3'b100};
      bins prot5 = {3'b101};
      bins prot6 = {3'b110};
      bins prot7 = {3'b111};
    }
    cp_oob  : coverpoint in_range {
      bins in_range  = {1'b1};
      bins out_range = {1'b0};
    }
    x_op_reg : cross cp_op, cp_reg iff (in_range);
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_axfe_access = new();
  endfunction

  function void write(axi4lite_seq_item t);
    op       = int'(t.op);
    reg_idx  = t.addr[4:2];
    resp     = t.resp;
    strb     = t.strb;
    prot     = t.prot;
    in_range = (t.addr[4:0] <= 5'h10);
    is_write = (t.op == WRITE);
    cg_axfe_access.sample();
  endfunction
endclass

`endif
