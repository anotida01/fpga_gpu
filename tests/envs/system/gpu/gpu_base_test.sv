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
  // test-side mechanism exists for it.

  // Scoreboard event hooks (for the future start/done/interrupt tests):
  function void report_gpu_done(); env.scb.report_gpu_done(); endfunction
  function void clear_gpu_done();  env.scb.clear_gpu_done();  endfunction

  // --- Framebuffer geometry (from c_model H_SIZE=320, V_SIZE=240; RTL depth.sv) ---
  // One 32-bit word per pixel, row-major: loc = ROP_BUF_WIDTH * y + x.
  localparam int ROP_BUF_WIDTH = 320;
  localparam int ROP_BUF_HEIGHT = 240;
  localparam int ROP_BUF_WORDS  = ROP_BUF_WIDTH * ROP_BUF_HEIGHT; // 76800 words

  // --- DUT shared-RAM address plan (host-bus view, 64 MB window at 0x0) --------
  // framebuffer (default OUT_MEM_OFF) : 0x0001_0000..0x0004_BFFF
  //   (pitch 256 32-bit words x 240 rows = 0x3C000 bytes, DE1-SoC geometry)
  // mesh seed base (byte address)     : 0x0005_0000, i.e. PAST the framebuffer
  //   region with a 16 KiB guard band; the largest current mesh (bunny,
  //   9,441,848 B) ends at 0x0095_33A8, still inside the 64 MB window.
  // Note on AXI bridging: host-bus RAM writes use physical byte addresses directly,
  // but the DMA read path's AXI bridge (wbm2axilite) scales Wishbone word addresses
  // by 4 (left-shifts by 2). Therefore, IN_MEM_OFF must be programmed as a word
  // offset (MESH_SEED_WORD_OFF = MESH_SEED_BYTE_OFF / 4 = 0x0001_4000).
  localparam logic [31:0] MESH_SEED_BYTE_OFF = 32'h0005_0000;
  localparam logic [31:0] MESH_SEED_WORD_OFF = MESH_SEED_BYTE_OFF / 32'd4; // 0x0001_4000

  // --- Mesh file locator ----------------------------------------------------
  // Resolve the mesh (.memh) file to seed the DUT-internal RAM.
  //   +MEMH    -- mesh filename      (default: box.memh)
  //   +MEMH_DIR-- directory holding it (abs path, set per-test in regression.vsif)
  // Falls back to the CWD-relative "memh/box.memh" (manual flow symlinks it)
  // when the plusargs are not supplied.
  function automatic string get_mesh_file();
    string dir, name;
    if (!$value$plusargs("MEMH=%s", name)) begin
      return "./memh/box.memh"; // Fallback if +MEMH=... is not specified
    end
    if ($value$plusargs("MEMH_DIR=%s", dir) && dir != "") begin
      return {dir, "/", name};
    end
    return name;
  endfunction

  // --- Done-Detection & Render Helpers (irq-line driven, no STATUS bus poll) --
  // Wait for the DUT's GPU done/irq line (dut.gpu0.irq_gpu) to assert, observed
  // directly via the irq_if probe. We intentionally do NOT poll STATUS over the
  // host bus -- the live irq line is the authoritative "done" signal, and the
  // scoreboard reads it live for STATUS (reg1) expected values, so no spurious
  // STATUS mismatch is raised. Timeout is generous (a full box render was
  // ~4.4ms of sim time ~= 440k+ clocks in the last run).
  task wait_gpu_done(int timeout_cycles = 10_000_000);
    virtual irq_if vif = env.scb.irq_vif;
    int elapsed = 0;
    if (vif == null) begin
      `uvm_fatal("NO_IRQ_IF", "env.scb.irq_vif is null; cannot wait for GPU done")
    end
    while (!vif.irq) begin
      @(posedge vif.clk);
      elapsed++;
      if (elapsed > timeout_cycles) begin
        `uvm_fatal("GPU_TIMEOUT", $sformatf("GPU did not assert irq (done) within %0d cycles", elapsed))
      end
    end
  endtask

  // Executes a complete render cycle:
  // 1. Configure input/output memory offsets
  // 2. Trigger start (CONTROL[0] = 1)
  // 3. Wait for done via the live irq line (no bus polling)
  // 4. Clear interrupt (INT_CLR[0] = 1)
  task render_one_frame(logic [31:0] in_offset = 32'h0, logic [31:0] out_offset = 32'h0001_0000);
    write_ctrl(REG_IN_MEM_OFF, in_offset);
    write_ctrl(REG_OUT_MEM_OFF, out_offset);
    write_ctrl(REG_CONTROL, 32'h1);
    wait_gpu_done();
    write_ctrl(REG_INT_CLR, 32'h1);
  endtask

endclass

`endif
