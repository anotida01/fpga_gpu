`ifndef IRQ_IF_SV
`define IRQ_IF_SV

// Observation conduit for the DUT's GPU interrupt / done line (irq_gpu).
// `clk` and `irq` are input ports so the testbench drives them hierarchically
// from dut.gpu0.irq_gpu (no RTL change, legal at module scope). Published to UVM
// via config_db so the scoreboard keeps STATUS (reg1) in step and the base
// test can wait on done via the live irq -- no host-bus STATUS polling.
interface irq_if(
  input logic clk,
  input logic irq
);
endinterface

`endif
