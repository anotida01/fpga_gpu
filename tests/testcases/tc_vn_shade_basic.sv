`ifndef TC_VN_SHADE_BASIC_SV
`define TC_VN_SHADE_BASIC_SV
`timescale 1ps/1ps
import uvm_pkg::*;
import pipe_pkg::*;
import vn_shade_env_pkg::*;
import vn_shade_seq_pkg::*;
`include "uvm_macros.svh"

class tc_vn_shade_basic extends vn_shade_base_test;
  `uvm_component_utils(tc_vn_shade_basic)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // -------------------------------------------------------------------
    // Frame 1: box light + 8 directed normals + 64-normal random sweep
    // -------------------------------------------------------------------
    wait_for_reset();

    `uvm_info("TC", "Frame 1: box light (10711, -10081, 7217), 8 directed normals, 64-normal sweep", UVM_LOW)

    // Light preamble (Q13.14, 1.0 = 16384): all three components non-zero
    // so a component desync is observable.
    send_light(27'sd10711, -27'sd10081, 27'sd7217);

    // Directed normals (Q13.14). Expected values are computed inline by the
    // scoreboard — never hardcoded here.
    send_normal(-27'sd16384, 27'sd0,      27'sd0);
    send_normal( 27'sd16384, 27'sd0,      27'sd0);
    send_normal( 27'sd0,     -27'sd16384, 27'sd0);
    send_normal( 27'sd0,      27'sd16384, 27'sd0);
    send_normal( 27'sd0,      27'sd0,    -27'sd16384);
    send_normal( 27'sd0,      27'sd0,      27'sd16384);
    send_normal( 27'sd8192,   27'sd8192,   27'sd8192);
    send_normal(-27'sd8192,   27'sd0,      27'sd8192);

    // Randomized sweep: 64 normals, each component in [-16384, 16384].
    repeat (64) begin
      vn_shade_normal_seq seq = vn_shade_normal_seq::type_id::create("seq");
      assert(seq.randomize() with {
        nx inside {[-16384:16384]};
        ny inside {[-16384:16384]};
        nz inside {[-16384:16384]};
      });
      seq.start(env.in_agent.sqr);
    end

    // Drain the DUT's output pipeline before the frame-boundary reset.
    wait_drained();

    // -------------------------------------------------------------------
    // Frame 2: reset + light re-latch
    // -------------------------------------------------------------------
    new_frame();

    `uvm_info("TC", "Frame 2: relatched light (-7217, 10081, 10711), 8 randomized normals", UVM_LOW)

    send_light(-27'sd7217, 27'sd10081, 27'sd10711);

    repeat (8) begin
      vn_shade_normal_seq seq = vn_shade_normal_seq::type_id::create("seq");
      assert(seq.randomize() with {
        nx inside {[-16384:16384]};
        ny inside {[-16384:16384]};
        nz inside {[-16384:16384]};
      });
      seq.start(env.in_agent.sqr);
    end

    wait_drained();

    #500ns;
    `uvm_info("TC", "Finished tc_vn_shade_basic transactions.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif
