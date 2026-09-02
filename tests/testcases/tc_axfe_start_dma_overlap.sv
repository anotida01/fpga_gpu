`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// START-DURING-DMA-IN-FLIGHT test for the front end (work order item 2C).
// Interleaves a GPU→DUT DMA fetch stream with a CPU `start` write and checks
// the three properties the work order asks for:
//   (a) NO START PREMATURE: DUT is in START (ready_i low) and the deferred
//       start does NOT fire while DMA is being serviced (assert_no_start_pulse).
//   (b) NO DMA CORRUPTION: every `send_dma_req` is matched by the scoreboard's
//       FIFO to a `dma_rsp` and compared to the seeded memory word
//       (axfe_scoreboard.sv:124-147); check_phase errors if the FIFO is
//       non-empty or the per-word data does not match.
//   (c) NO DEADLOCK: after releasing the GPU (ready_i high) the deferred start
//       fires (wait_start_pulse), the done cycle completes (Reg1=1, Reg0=0),
//       and the test finishes cleanly. A hang in any DUT state machine
//       (axil_dma_master, bus_sm, gpu_sm) would blow the UVM timeout in the
//       simulation shell and show up as an error in the log - this test relies
//       on `wait_start_pulse` + `read_reg` returning for the "no deadlock"
//       claim, and on scoreboard `check_phase` for the stream-completes claim.
//
// Note: in this simplified DUT (axil.sv) the CTRL slave path
// (axlite2wbsp -> axil_ctrl_slave -> regfile) and the DMA master path
// (axil_dma_master -> wbm2axilite -> mstr_agent mem model) do not share an
// on-chip resource; the 2x1 axil_interconnect_wrap_2x1 vfile is present in
// the repo but is NOT instantiated in the AXFE front end (see the TODO at
// axil.sv:182). "No deadlock" therefore means each DUT state machine
// terminates, not that a shared bus is contended. This is the front-end
// scope; the real 2x1 contention case is out of scope here and would land
// with a top-level integration test.
class tc_axfe_start_dma_overlap extends axfe_base_test;
  `uvm_component_utils(tc_axfe_start_dma_overlap)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Wait for reset release and let the design settle (axil_dma_master out
    // of RESET, bus_sm out of its init, gpu_sm in IDLE).
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("2C", "Start-during-DMA-in-flight test: no corruption, no deadlock, no early start", UVM_LOW)

    // 1. Put the GPU in the BUSY state (ready_i low) so the DUT can latch a
    //    start but cannot launch (gpu_sm waits in START) - same setup as 2A.
    set_done(1'b0);
    repeat(2) @(posedge env.ctrl_agent.vif.clk);

    // 2. Seed the memory model with 4 distinct 32-bit words at byte
    //    offsets 0x0, 0x4, 0x8, 0xC. The scoreboard's per-word FIFO
    //    (exp_dma_addr_q, axfe_scoreboard.sv:42) will expect exactly these
    //    words back in order as the DUT services the DMA requests.
    env.mem.write(32'h00, 32'habababab);
    env.mem.write(32'h04, 32'habcd1234);
    env.mem.write(32'h08, 32'h1234abcd);
    env.mem.write(32'h0C, 32'hffffdddd);

    // 3. First DMA fetch (word 0) - exercises the DMA master path end-to-end:
    //    pipe driver -> axil_dma_master -> wbm2axilite -> mstr_agent -> mem.
    //    The pipe driver holds valid until ready_o pulses (accept), then the
    //    DUT is in WAIT_ACK/DONE and ready_o is low (axil_dma.sv:66,
    //    axil_dma.sv:98, axil_dma.sv:105). A second send_dma_req issued now
    //    will stall the pipe driver (pipe_pkg.sv:44) until the DUT returns to
    //    IDLE, which is what makes the next steps genuinely "DMA in flight".
    send_dma_req(0);

    // 4. Issue the CPU `start` while the DUT is servicing the #0 DMA fetch.
    //    DUT is in gpu_sm::START (latched start, deferred), axil_dma_master
    //    is in WAIT_ACK/DONE. The DUT must honor the start without corrupting
    //    the DMA stream (property a) or deadlocking the DMA path (property c).
    write_reg(32'h00, 32'h1); // Reg0 bit0 = start

    // 5. DEFER, NOT DROP: confirm no `gpu_start` pulse fires while DMA is
    //    still in flight. The deferred start fires later (in step 8).
    assert_no_start_pulse(20);
    `uvm_info("2C", "OK: start deferred while DMA in flight (no early gpu_start)", UVM_LOW)

    // 6. Complete the DMA burst (words 1, 2, 3). The pipe driver serializes
    //    these: each send_dma_req returns only after the DUT accepts it, so
    //    a req is in flight between consecutive send_dma_req calls.
    //    Scoreboard: each req pushes a byte-addr to exp_dma_addr_q and each
    //    rsp pops the head and compares against mem_model.read(...).
    send_dma_req(1);
    send_dma_req(2);
    send_dma_req(3);
    `uvm_info("2C", "OK: 4 DMA reqs issued while start was deferred", UVM_LOW)

    // 7. Prove the CTRL bus is still alive while DMA finished and the start
    //    is latched (no lockup): scoreboard-checked readbacks of Reg3 and
    //    Reg4. These are plain stored registers (axil_control.sv:395-396,
    //    399, 43-49). Reg0 (start bit) reads as 1 because it was latched and
    //    has not yet been cleared in DONE (axil_control.sv:214-219: start
    //    is cleared only when the done cycle completes, which needs ready_i).
    write_reg(32'h0C, 32'h12345678); // Reg3 IN_MEM_OFF
    write_reg(32'h10, 32'ha5a55a5a); // Reg4 OUT_MEM_OFF
    read_reg(32'h0C); // Reg3 readback == 0x12345678 (scoreboard-checked)
    read_reg(32'h10); // Reg4 readback == 0xA5A55A5A (scoreboard-checked)
    read_reg(32'h00); // Reg0 start bit still latched -> expect 1
    `uvm_info("2C", "OK: CTRL bus not locked while DMA finished and start latched", UVM_LOW)

    // 8. Release the GPU: ready_i high. The DEFERRED start now fires
    //    (START -> WAIT, axil_control.sv:196-202), the DUT completes
    //    WAIT -> DONE (axil_control.sv:214-219) and self-clears the start
    //    bit (REG0 bit0 <- 0); intr_gen latches the done interrupt. This step
    //    exercises 2C's "no deadlock" claim - if axil_dma_master, bus_sm, or
    //    gpu_sm had hung in any in-flight state, this wait would time out and
    //    the test would report a UVM_ERROR (wait_start_pulse timeout).
    set_done(1'b1);
    wait_start_pulse(50);
    `uvm_info("2C", "OK: deferred start fired on GPU release (no deadlock)", UVM_LOW)
    repeat(6) @(posedge env.ctrl_agent.vif.clk);

    // 9. The start->done cycle completed: interrupt latched (Reg1=1), start
    //    bit self-cleared (Reg0=0). Sync the model and confirm both.
    report_gpu_done();
    read_reg(32'h04); // Reg1 STATUS = 1 (interrupt latched)
    sync_reg_model(0, 32'h0);
    read_reg(32'h00); // Reg0 start bit = 0 (self-cleared)
    `uvm_info("2C", "OK: deferred start honored; start bit cleared, irq latched", UVM_LOW)

    // 10. Leave the environment in a clean state.
    set_done(1'b0);
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
