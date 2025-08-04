module top ();

  tb_axil_interconnect tb();

  initial begin

    // we need to fill the memory with an object
    $readmemh("memh/box.memh", tb.dut.axil_ram0.mem);

    // start all testbench components
    tb.start_clk(10);
    tb.reset_dut();


    tb.axi_write('h1000000 +(4 *'h4), 'h10_0000); // location of vram

    // start the gpu
    tb.axi_write('h1000000, 'h1);

    // wait for interrupt
    wait (tb.dut.gpu0.irq_gpu);
    assert(tb.dut.gpu0.irq_gpu === 1);

    tb.axi_write('h1000008, 1'h1); // clear interrupt
    assert(tb.dut.gpu0.irq_gpu === 0);

    tb.wait_clk(50);
    $finish;

  end


endmodule