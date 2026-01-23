`timescale 1ps/1ps

interface axi4lite_intf #(
    parameter DATA_WIDTH = 32,  // Width of data bus in bits
    parameter ADDR_WIDTH = 32   // Width of address bus in bits
);

  // Clock and Reset
  logic clk;
  logic rst;

  // Address Channel (AW) - Write Address 
  logic [ADDR_WIDTH-1:0] awaddr; // Write address
  logic [2:0] awprot;   // Write protection (read/write)
  logic awvalid;         // Address valid signal
  logic awready;         // Address ready signal

  // Data Channel (W) - Write Data 
  logic [DATA_WIDTH-1:0] wdata;    // Write data
  logic [DATA_WIDTH/8-1:0] wstrb;     // Byte enable strobe
  logic wvalid;          // Write data valid signal
  logic wready;           // Write data ready signal

  // Response Channel (B) - Write Response
  logic bvalid;          // Response valid signal
  logic [1:0] bresp;    // Response (OKAY/ERROR)
  logic bready;           // Response ready signal

 // Address Channel (AR) - Read Address
  logic [ADDR_WIDTH-1:0] araddr;   // Read address
  logic [2:0] arprot;    // Read protection
  logic arvalid;          // Read address valid
  logic arready;          // Read address ready


 // Data Channel (R) - Read Response
  logic rvalid;           // Read data valid
  logic [DATA_WIDTH-1:0] rdata;     // Read data
  logic [1:0] rresp;      // Read response (OKAY/ERROR)
  logic rready;           // Read data ready


  // Modification Ports 

  modport master (input clk, input rst,
                  output awaddr, output awprot, output awvalid,
                  input awready,

                  output wdata, output wstrb, output wvalid,
                  input wready,

                  input bvalid, input bresp, 
                  output bready,

                  output araddr, output arprot, output arvalid,
                  input arready,

                  input rvalid, input rdata, input rresp,
                  output rready);

  modport slave (input clk, input rst,
                input awaddr, input awprot, input awvalid,
                output awready,

                input wdata, input wstrb, input wvalid,
                output wready,

                output bvalid, output bresp, 
                input bready,

                input araddr, input arprot, input arvalid,
                output arready,

                output rvalid, output rdata, output rresp,
                input rready);
endinterface : axi4lite_intf 