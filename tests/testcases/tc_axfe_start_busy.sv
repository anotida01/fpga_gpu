`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// START-WHILE-GPU-BUSY test for the front end (work order item 2A).
// Drives a CPU `start` write (Reg0 bit0) while the GPU is still busy
// (gpu_ctrl_done / ready_i is low), then verifies the two properties the
// work order calls out:
//   (a) DEFER, not drop: the DUT latches the start (stays in gpu_sm START)
//       and does NOT emit the gpu_start pulse while ready is low
//       (axil_control.sv:196-202 fires the pulse only when gpu_ready_i).
//   (b) NO CTRL-BUS LOCKUP: while stalled in START, other control-register
//       writes/reads still complete and are scoreboard-checked. This holds
//       because en_wr_p1 is gated by gpu_sm_en_wr_p1 (en_p1_o), which is 0
//       only in WAIT (axil_control.sv:207) — in START it is 1, and reads are
//       gated by bus_sm alone (axil_control.sv:304-316, 114-115).
// Finally, releasing the GPU (set_done(1'b1)) makes the *deferred* start fire
// (waits on wait_start_pulse), completing WAIT->DONE and self-clearing the
// start bit (axil_control.sv:214-219) — proving the start was deferred and
// honored rather than dropped, and leaving the scoreboard model clean.
//
// Note: the work order's original 2A wording says the DUT waits "until
// regf_start_i clears AND ready_i". The RTL clears regf_start only in DONE
// (axil_control.sv:214-219) and transitions START->WAIT on ready_i alone
// (axil_control.sv:196-202); the start bit is not cleared as the release
// condition, it is cleared *as a result*. This test asserts the RTL behavior.
class tc_axfe_start_busy extends axfe_base_test;
  `uvm_component_utils(tc_axfe_start_busy)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for reset release and let the design settle.
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("2A", "Start-while-busy test: deferral + no CTRL-bus lockup", UVM_LOW)

    // 1. Put the GPU in the BUSY state: gpu_ctrl_done (ready_i) low, so the
    //    DUT is ready to latch a start but cannot launch (gpu_sm waits in START).
    set_done(1'b0);
    repeat(2) @(posedge env.ctrl_agent.vif.clk);

    // 2. Write 1 to the start bit (Reg0 bit[0]) via a CTRL write. The DUT moves
    //    IDLE->START (axil_control.sv:189-193) and latches the start; with
    //    ready_i low it MUST stay in START and not fire the gpu_start pulse.
    write_reg(32'h00, 32'h1);

    // 3. DEFER, NOT DROP: assert that no gpu_start pulse is emitted while the
    //    GPU is busy. A premature pulse here would be a DUT bug (launching with
    //    ready_i low). The DUT should hold the start for when ready asserts.
    assert_no_start_pulse(20);
    `uvm_info("2A", "OK: start deferred (gpu_start held low while GPU busy)", UVM_LOW)

    // 4. NO CTRL-BUS LOCKUP: while the DUT is stalled in START, verify other
    //    control-register traffic still completes and is scoreboard-checked.
    //    Writes land (en_p1_o is 1 in START, axil_control.sv:204-211 does not
    //    gate them) and reads are gated by bus_sm alone.
    write_reg(32'h0C, 32'h12345678); // Reg3 IN_MEM_OFF
    write_reg(32'h10, 32'ha5a55a5a); // Reg4 OUT_MEM_OFF
    read_reg(32'h0C); // expect 0x12345678 (scoreboard-checked)
    read_reg(32'h10); // expect 0xA5A55A5A (scoreboard-checked)
    read_reg(32'h00); // start bit still latched -> expect 1
    read_reg(32'h04); // no start->done yet -> STATUS/irq stays 0
    `uvm_info("2A", "OK: CTRL bus not locked while start is deferred", UVM_LOW)

    // 5. Release the GPU: ready_i high. The DEFERRED start now fires
    //    (START->WAIT emits the pulse), the DUT completes WAIT->DONE and
    //    self-clears the start bit, and intr_gen latches the done interrupt.
    set_done(1'b1);
    wait_start_pulse(50);
    `uvm_info("2A", "OK: deferred start fired on GPU release", UVM_LOW)
    repeat(6) @(posedge env.ctrl_agent.vif.clk);

    // 6. The start->done cycle completed: interrupt latched (Reg1=1), start bit
    //    self-cleared (Reg0=0). Sync the scoreboard model and confirm both.
    report_gpu_done();
    read_reg(32'h04); // Reg1 STATUS = 1 (interrupt latched)
    sync_reg_model(0, 32'h0);
    read_reg(32'h00); // Reg0 start bit = 0 (self-cleared)
    `uvm_info("2A", "OK: deferred start honored; start bit self-cleared, irq latched", UVM_LOW)

    set_done(1'b0);
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
