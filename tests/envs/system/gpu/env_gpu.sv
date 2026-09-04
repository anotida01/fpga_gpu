`ifndef ENV_GPU_SV
`define ENV_GPU_SV

// System environment for axil_sys_top. The DUT's *only* external boundary is its
// exported s00 AXI4-Lite host port, so a single host agent (UVM master driving it,
// UVM slave answering it) plus the reference scoreboard covers every host-visible
// behavior. The DUT's internal crossbar, axil_ram0, and gpu0 are exercised purely
// through that host bus - we never drive or poke internal DUT nets from here.
class env_gpu extends uvm_env;
  axi4lite_agent  host_agent; // s00 CPU AXI4-Lite port (UVM drives & answers)
  clk_rst_ctrl    clk;
  gpu_scoreboard  scb;
  axi4lite_mem_model mem; // shared reference model for the RAM region (axil_ram0)

  `uvm_component_utils(env_gpu)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    host_agent = axi4lite_agent::type_id::create("host_agent", this);
    host_agent.is_master = 1; // UVM is the master; DUT is the slave

    clk = clk_rst_ctrl::type_id::create("clk", this);
    scb = gpu_scoreboard::type_id::create("scb", this);
    mem = axi4lite_mem_model::type_id::create("mem", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    host_agent.mon.ap.connect(scb.host_export);
    scb.mem_model = mem;
    // A future RAM-boundary agent (responder answering the crossbar's RAM master
    // port) would take `s_drv.mem_model = mem;` here. The smoke test (control
    // registers only) does not attach one yet.
  endfunction
endclass

`endif
