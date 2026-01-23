/*
* The overall purpose of this test to ensure that the GPU is able draw multiple frames without locking up
*
*/




module top ();

  tb_axil_interconnect tb();

  initial begin

    // we need to fill the memory with an object
    $readmemh("memh/box.memh", tb.dut.axil_ram0.mem);

    // start all testbench components
    tb.start_clk(10);
    tb.reset_dut();

    // start the gpu
    tb.axi_write('h1000000, 'h1);

    // wait for interrupt
    wait (tb.dut.gpu0.irq_gpu);
    assert(tb.dut.gpu0.irq_gpu === 1);

    tb.axi_write('h1000008, 1'h1); // clear interrupt
    assert(tb.dut.gpu0.irq_gpu === 0);

    // we now need to check the contents of the framebuffer

    // then repeat the process many times, each time changing the write address

    // check that the same frame is produced each time!

    // we should probably loop many 60 times? not sure... 

    // there might be some HW changes to do with how the Z buffer is handled...

    tb.wait_clk(50);
    $finish;

  end


endmodule