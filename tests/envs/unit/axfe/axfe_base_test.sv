`ifndef AXFE_BASE_TEST_SV
`define AXFE_BASE_TEST_SV

class axfe_base_test extends uvm_test;
  `uvm_component_utils(axfe_base_test)

  env_axfe env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    env = env_axfe::type_id::create("env", this);
  endfunction

  task write_reg(logic [31:0] addr, logic [31:0] data);
    axfe_axil_write_seq seq = axfe_axil_write_seq::type_id::create("seq");
    seq.addr = addr;
    seq.data = data;
    seq.start(env.ctrl_agent.sqr);
  endtask

  task read_reg(logic [31:0] addr);
    axfe_axil_read_seq seq = axfe_axil_read_seq::type_id::create("seq");
    seq.addr = addr;
    seq.start(env.ctrl_agent.sqr);
  endtask

  task send_dma_req(logic [31:0] addr);
    axfe_dma_req_seq seq = axfe_dma_req_seq::type_id::create("seq");
    seq.addr = addr;
    seq.start(env.dma_req_agent.sqr);
  endtask

  task seed_memory(int num_words, logic [31:0] base_addr = 32'h0);
    for (int i = 0; i < num_words; i++) begin
      env.mem.write(base_addr + (i * 4), 32'h10000000 + i);
    end
  endtask

endclass

`endif
