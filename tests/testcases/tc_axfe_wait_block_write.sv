`timescale 1ps/1ps
import uvm_pkg::*;
import axi4lite_pkg::*;
import pipe_pkg::*;
import gpu_hs_pkg::*;
import axfe_env_pkg::*;
import axfe_seq_pkg::*;
`include "uvm_macros.svh"

// Busy-state CPU write-blocking test.
//
// Verifies that CPU writes are rejected when the device is in a busy processing
// state. A write that the device chooses not to honor must return an error
// response (not OKAY) to avoid silent data loss.
//
// This test is designed to fail against the current design to document a
// known deficiency where blocked writes return success status.

class tc_axfe_wait_block_write extends axfe_base_test;
  `uvm_component_utils(tc_axfe_wait_block_write)

  localparam logic [1:0] RESP_OKAY = 2'b00;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    logic [1:0] blocked_resp;
    phase.raise_objection(this);

    // Wait for reset release and let the design settle.
    wait(env.ctrl_agent.vif.rst_n === 1'b1);
    repeat(5) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("TEST", "Busy-state write-rejection test: a write issued while the device is busy must be REJECTED, not silently accepted", UVM_LOW)

    // Set initial device state to busy.
    set_done(1'b0);
    repeat(2) @(posedge env.ctrl_agent.vif.clk);

    // Establish baseline value in a target register while the device is idle.
    write_reg(32'h0C, 32'h12345678);
    repeat(2) @(posedge env.ctrl_agent.vif.clk);

    // Trigger operation start while device is busy.
    write_reg(32'h00, 32'h1);
    repeat(3) @(posedge env.ctrl_agent.vif.clk);

    // Transit to the processing state where write-blocking is active.
    set_done(1'b1);
    wait_start_pulse(50);
    // Hold device in the busy processing state.
    set_done(1'b0);
    repeat(3) @(posedge env.ctrl_agent.vif.clk); 

    `uvm_info("TEST", "Device is now busy: issuing write to be rejected", UVM_LOW)

    // Issue write while busy: this should be rejected by the device.
    write_capture_resp(32'h0C, 32'hDEADBEEF, blocked_resp);
    repeat(2) @(posedge env.ctrl_agent.vif.clk);

    `uvm_info("TEST", $sformatf("Captured response for blocked write = %b", blocked_resp), UVM_LOW)

    // ASSERT INTENDED BEHAVIOR: a write that cannot be serviced must return an error response.
    // The current design deficiency is that it returns success (OKAY) while dropping the data.
    if (blocked_resp == RESP_OKAY) begin
      `uvm_error("TEST", "Deficiency detected: write during busy state was silently dropped but returned success status (intended: error response)")
    end else begin
      `uvm_info("TEST", "OK: blocked write correctly returned an error response", UVM_LOW)
    end

    // Verify the baseline value remains intact (write was not stored).
    // Reconcile model with unchanged device state for check.
    sync_reg_model(3, 32'h12345678);
    read_reg(32'h0C); 
    `uvm_info("TEST", "Confirmed baseline value is intact (no silent corruption)", UVM_LOW)

    // Move to idle state.
    set_done(1'b1);
    repeat(6) @(posedge env.ctrl_agent.vif.clk);
    report_gpu_done();

    // Verify writes land normally when device is no longer busy.
    write_reg(32'h0C, 32'hCAFE0000);
    read_reg(32'h0C);
    `uvm_info("TEST", "Confirmed post-busy write lands normally", UVM_LOW)

    // Leave the environment in a clean state.
    set_done(1'b0);
    #100ns;
    phase.drop_objection(this);
  endtask

endclass
