`ifndef ENV_AXFE_SV
`define ENV_AXFE_SV

class env_axfe extends uvm_env;
  axi4lite_agent ctrl_agent;
  axi4lite_agent mstr_agent;
  pipe_agent     dma_req_agent;
  pipe_agent     dma_rsp_agent;
  
  axfe_scoreboard scb;
  axi4lite_mem_model mem;

  `uvm_component_utils(env_axfe)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    ctrl_agent = axi4lite_agent::type_id::create("ctrl_agent", this);
    ctrl_agent.is_master = 1;
    
    mstr_agent = axi4lite_agent::type_id::create("mstr_agent", this);
    mstr_agent.is_master = 0; // Slave/Responder
    
    dma_req_agent = pipe_agent::type_id::create("dma_req_agent", this);
    dma_req_agent.is_responder = 0; // Drives req
    
    dma_rsp_agent = pipe_agent::type_id::create("dma_rsp_agent", this);
    dma_rsp_agent.is_responder = 1; // Samples resp, drives ready
    
    scb = axfe_scoreboard::type_id::create("scb", this);
    mem = axi4lite_mem_model::type_id::create("mem", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    ctrl_agent.mon.ap.connect(scb.ctrl_export);
    dma_req_agent.mon.ap.connect(scb.dma_req_export);
    dma_rsp_agent.mon.ap.connect(scb.dma_rsp_export);
    scb.mem_model = mem;
    mstr_agent.s_drv.mem_model = mem;
  endfunction
endclass

`endif
