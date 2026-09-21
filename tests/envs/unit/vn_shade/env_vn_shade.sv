`ifndef ENV_VN_SHADE_SV
`define ENV_VN_SHADE_SV

class env_vn_shade extends uvm_env;
  pipe_agent#(.DATA_W(27)) in_agent;
  pipe_agent#(.DATA_W(27)) out_agent;

  clk_rst_ctrl clk;
  vn_shade_scoreboard scb;

  `uvm_component_utils(env_vn_shade)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    clk = clk_rst_ctrl::type_id::create("clk", this);

    in_agent = pipe_agent#(.DATA_W(27))::type_id::create("in_agent", this);
    in_agent.is_responder = 0; // Drives input stream

    out_agent = pipe_agent#(.DATA_W(27))::type_id::create("out_agent", this);
    out_agent.is_responder = 1; // Responder / sink

    scb = vn_shade_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // drv is created during out_agent.build_phase, which runs after this
    // component's build_phase (top-down order), so defer this assignment
    // until after the build phase tree has fully completed.
    out_agent.drv.std_sink = 1; // Standard sink: drive ready_i=1 continuously

    in_agent.mon.ap.connect(scb.in_export);
    out_agent.mon.ap.connect(scb.out_export);
  endfunction

endclass

`endif
