`ifndef GPU_BASE_TEST_SV
`define GPU_BASE_TEST_SV

// Base test for every env_gpu (system) testcase. Builds the env and exposes the
// test-facing driver tasks. Address helpers bake in the host-bus map defined in
// gpu_env_pkg so a test writes/reads by register word index, not by raw address.
class gpu_base_test extends uvm_test;
  `uvm_component_utils(gpu_base_test)

  env_gpu env;

  // Control word indices (see gpu_env_pkg / README register map):
  //   0x00 CONTROL  0x04 STATUS  0x08 INT_CLR  0x0C IN_MEM_OFF  0x10 OUT_MEM_OFF
  localparam int REG_CONTROL     = 0;
  localparam int REG_STATUS      = 1;
  localparam int REG_INT_CLR     = 2;
  localparam int REG_IN_MEM_OFF  = 3;
  localparam int REG_OUT_MEM_OFF = 4;

  // Results captured by the most recent host-bus op (so a test can assert directly;
  // the scoreboard remains the authoritative check).
  logic [31:0] last_rdata;
  logic [1:0]  last_bresp;
  logic [1:0]  last_rresp;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    env = env_gpu::type_id::create("env", this);
  endfunction

  // --- Reset / clock (shared clk_rst controller) -------------------------------
  task do_reset(int hold_cycles = 2);
    env.clk.apply_reset(hold_cycles);
    env.scb.model_reset();
  endtask

  task stop_clk();
    env.clk.stop_clk();
  endtask

  task resume_clk();
    env.clk.resume_clk();
  endtask

  function void set_clk_period_ns(real period_ns);
    env.clk.set_clk_period_ns(period_ns);
  endfunction

  // --- Host-bus primitives (drive the DUT's exported s00 CPU port) ------------
  // Write a full 32-bit word at a host-bus address. Captures the DUT bresp.
  task write_reg(logic [31:0] addr, logic [31:0] data,
                 logic [3:0] strb = 4'hF, logic [2:0] prot = 3'h0);
    gpu_axil_write_seq seq = gpu_axil_write_seq::type_id::create("seq");
    seq.addr = addr;
    seq.data = data;
    seq.strb = strb;
    seq.prot = prot;
    seq.start(env.host_agent.sqr);
    last_bresp = seq.resp;
  endtask

  // Read a full 32-bit word at a host-bus address. Captures the DUT rdata/rresp.
  // (The scoreboard is the authoritative check; the capture is for test convenience.)
  task read_reg(logic [31:0] addr, logic [2:0] prot = 3'h0);
    gpu_axil_read_seq seq = gpu_axil_read_seq::type_id::create("seq");
    seq.addr = addr;
    seq.prot = prot;
    seq.start(env.host_agent.sqr);
    last_rdata = seq.data;
    last_rresp = seq.resp;
  endtask

  // --- Control-register convenience (by word index, baked-in host base) --------
  function logic [31:0] ctrl_addr(int word);
    return gpu_env_pkg::GPU_CTRL_BASE + (word * 32'd4);
  endfunction

  task write_ctrl(int word, logic [31:0] data);
    write_reg(ctrl_addr(word), data);
  endtask

  task read_ctrl(int word);
    read_reg(ctrl_addr(word));
  endtask

  // --- Future hook: seed the DUT's shared RAM (mesh load) ----------------------
  // NOT implemented here: a package cannot form a hierarchical name to the DUT
  // (SV LRM 6.4 - xmvlog ILLHIN), so when the render/golden tests arrive this
  // must be a task placed at TB MODULE scope (tb_gpu.sv) that calls
  //    $readmemh(mesh_name, dut.axil_ram0.mem);
  // and is reached via a virtual-if handle or a plain task passed to the test.
  // The memh path is the only route into the DUT-internal axil_ram0; no other
  // test-side mechanism exists for it. See workorder §7 and History.

  // Scoreboard event hooks (for the future start/done/interrupt tests):
  function void report_gpu_done(); env.scb.report_gpu_done(); endfunction
  function void clear_gpu_done();  env.scb.clear_gpu_done();  endfunction

endclass

`endif
