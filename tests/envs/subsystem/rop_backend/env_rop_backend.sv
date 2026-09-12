`ifndef ENV_ROP_BACKEND_SV
`define ENV_ROP_BACKEND_SV

// Subsystem env for axil_rop_backend:
//   in_agent  (pipe_agent, DATA_W=96)  -- drives the (x, y, c) pixel stream on
//               the DUT's valid/ready input; the monitor feeds the scoreboard.
//   out_agent (axi4lite_agent, slave)  -- responder at the DUT's write-only
//               AXI4-Lite master port; the monitor feeds the scoreboard.
//   scb                       -- golden pixel->write scoreboard (see
//               rop_backend_scoreboard.sv for the reference contract).

class env_rop_backend extends uvm_env;
  pipe_agent#(.DATA_W(96)) in_agent;
  axi4lite_agent           out_agent;

  clk_rst_ctrl clk;

  rop_backend_scoreboard scb;

  `uvm_component_utils(env_rop_backend)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    clk = clk_rst_ctrl::type_id::create("clk", this);

    in_agent = pipe_agent#(.DATA_W(96))::type_id::create("in_agent", this);
    in_agent.is_responder = 0; // Drives the input pixel stream (valid/data)

    out_agent = axi4lite_agent::type_id::create("out_agent", this);
    out_agent.is_master = 0; // Slave/responder: the DUT is the write master

    scb = rop_backend_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    in_agent.mon.ap.connect(scb.in_export);
    out_agent.mon.ap.connect(scb.axi_export);
  endfunction

endclass

`endif
