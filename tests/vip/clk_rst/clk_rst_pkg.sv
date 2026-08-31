package clk_rst_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class clk_rst_ctrl extends uvm_component;
    virtual clk_rst_if vif;

    uvm_event reset_done_evt;
    bit reset_done = 1'b0;

    `uvm_component_utils(clk_rst_ctrl)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      reset_done_evt = new("reset_done_evt");
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual clk_rst_if)::get(this, "", "vif", vif)) begin
        `uvm_fatal("CLK_RST_VIF", "Could not get virtual clk_rst_if from config_db")
      end
    endfunction

    task run_phase(uvm_phase phase);
      fork
        clk_gen();
        rst_gen();
      join_none
    endtask

    protected task clk_gen();
      vif.clk <= 1'b0;
      forever begin
        if (vif.clk_en) begin
          #(vif.clk_period / 2.0);
          vif.clk <= 1'b1;
          #(vif.clk_period / 2.0);
          vif.clk <= 1'b0;
        end else begin
          vif.clk <= 1'b0;
          #100ps;
        end
      end
    endtask

    protected task rst_gen();
      int rst_len = 10;
      vif.rst_n <= 1'b0;
      reset_done = 1'b0;
      if (uvm_config_db#(int)::get(this, "", "rst_len", rst_len)) begin
        `uvm_info("CLK_RST", $sformatf("Configured initial reset length: %0d cycles", rst_len), UVM_MEDIUM)
      end
      repeat (rst_len) @(posedge vif.clk);
      vif.rst_n <= 1'b1;
      reset_done = 1'b1;
      reset_done_evt.trigger();
      `uvm_info("CLK_RST", "Initial reset released", UVM_MEDIUM)

      forever begin
        @(negedge vif.clk);
        if (vif.reset_req === 1'b1) begin
          vif.rst_n <= 1'b0;
          reset_done = 1'b0;
        end else begin
          if (!reset_done) begin
            vif.rst_n <= 1'b1;
            reset_done = 1'b1;
            reset_done_evt.trigger();
          end
        end
      end
    endtask

    task apply_reset(int hold_cycles = 2);
      `uvm_info("CLK_RST", $sformatf("Triggering reset assertion for %0d cycles...", hold_cycles), UVM_LOW)
      vif.reset_req <= 1'b1;
      repeat (hold_cycles) @(posedge vif.clk);
      vif.reset_req <= 1'b0;
      @(posedge vif.clk);
      wait(reset_done);
      `uvm_info("CLK_RST", "Reset re-assertion complete and released", UVM_LOW)
    endtask

    task stop_clk();
      `uvm_info("CLK_RST", "Stopping clock (clk_en = 0)", UVM_LOW)
      vif.clk_en <= 1'b0;
    endtask

    task resume_clk();
      `uvm_info("CLK_RST", "Resuming clock (clk_en = 1)", UVM_LOW)
      vif.clk_en <= 1'b1;
    endtask

    function void set_clk_period_ns(real period_ns);
      `uvm_info("CLK_RST", $sformatf("Setting clock period to %0.2f ns", period_ns), UVM_LOW)
      vif.clk_period = period_ns * 1000.0;
    endfunction

  endclass

endpackage
