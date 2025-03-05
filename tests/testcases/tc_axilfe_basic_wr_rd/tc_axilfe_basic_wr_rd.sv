/*
1. Tests that reads initiated by the GPU (WB) can reach the AXIL subsystem and correctly access memory
i.e. The GPU is able to fetch data. The GPU does not write to memory using the front end interface

2. Tests that writes from the AXIL subsystem are converted to WB and take have an effect on the GPU regs.
Writes and reads GPU regs
*/

module top;

  tb_axil_front_end tb();

  initial begin

    int unsigned rdata;

    // start all testbench components
    tb.start_clk(10);
    tb.reset_dut();
    tb.start_axi_bus_responder();
    tb.start_dma_tx_monitor();

    // send a DMA request as the GPU
    tb.mem['h0] = 32'habababab; // insert some dummy data - these are byte address as seen by the AXI Intf
    tb.mem['h4] = 32'habcd1234; // insert some dummy data - these are byte address as seen by the AXI Intf
    tb.mem['h8] = 32'h1234abcd; // insert some dummy data - these are byte address as seen by the AXI Intf
    tb.mem['hc] = 32'hffffdddd; // insert some dummy data - these are byte address as seen by the AXI Intf
    tb.gpu_dma_ready <= 1; // this has to be controlled by monitor/responder?

    tb.gpu_read_req(0); // note that these are 32-word addresses as seen by the WB Intf
    tb.gpu_read_req(1); // note that these are 32-word addresses as seen by the WB Intf
    tb.gpu_read_req(2); // note that these are 32-word addresses as seen by the WB Intf
    tb.gpu_read_req(3); // note that these are 32-word addresses as seen by the WB Intf
    do tb.wait_clk(); while (tb.dma_tx_q.size() != 4);

    assert (tb.dma_tx_q[0].resp_data === 'habababab);
    assert (tb.dma_tx_q[1].resp_data === 'habcd1234);
    assert (tb.dma_tx_q[2].resp_data === 'h1234abcd);
    assert (tb.dma_tx_q[3].resp_data === 'hffffdddd);

    tb.wait_clk(100);


    // let's try some write/reads to the CTRL regs
    tb.axi_write('h0, 'hdeadbeef);
    tb.axi_write('h4, 'h51515151);
    tb.axi_write('h8, 'ha5a5a5a5);
    tb.axi_write('hc, 'h12345678);
    tb.wait_clk(50);
    tb.axi_read('h0, rdata); assert (rdata === 'hdeadbeef);
    tb.axi_read('h4, rdata); assert (rdata === 'h51515151);
    tb.axi_read('h8, rdata); assert (rdata === 'ha5a5a5a5);
    tb.axi_read('hc, rdata); assert (rdata === 'h12345678);
    tb.wait_clk(50);

    $finish;

  end

endmodule

