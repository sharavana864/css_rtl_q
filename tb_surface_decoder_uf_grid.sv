`timescale 1ns / 1ps

module tb_surface_decoder_uf_grid;

    logic        aclk;
    logic        aresetn;

    // AXI4-Stream Slave (Syndrome Input)
    logic [7:0]  s_axis_tdata;
    logic        s_axis_tvalid;
    wire         s_axis_tready;

    // AXI4-Stream Master (18-bit Correction Output)
    wire  [17:0] m_axis_tdata;
    wire  [7:0]  m_axis_tuser;
    wire         m_axis_tvalid;
    logic        m_axis_tready;

    // Split output wires for easy viewing in Verdi nWave
    wire  [8:0]  pauli_x_correction = m_axis_tdata[8:0];
    wire  [8:0]  pauli_z_correction = m_axis_tdata[17:9];

    // Instantiate DUT
    surface_decoder_uf_grid dut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tuser  (m_axis_tuser),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready)
    );

    // 200 MHz Clock (5.0 ns period)
    initial aclk = 0;
    always #2.5 aclk = ~aclk;

    // Dump FSDB Waveform for Synopsys Verdi
    initial begin
        $fsdbDumpfile("uf_grid_decoder.fsdb");
        $fsdbDumpvars(0, tb_surface_decoder_uf_grid, "+all");
        $fsdbDumpflush;
    end

    // Task to inject syndrome and print decoded X/Z masks
    task inject_syndrome(input [3:0] sx_in, input [3:0] sz_in, input string test_name);
        begin
            @(posedge aclk);
            s_axis_tdata  <= {sx_in, sz_in};
            s_axis_tvalid <= 1'b1;

            wait (s_axis_tready == 1'b1);
            @(posedge aclk);
            s_axis_tvalid <= 1'b0;

            wait (m_axis_tvalid == 1'b1);
            $display("---------------------------------------------------------------");
            $display("[TEST: %s @ %0t ns]", test_name, $time);
            $display("  Syndrome In       : 8'h%02h (X-Stab[7:4]=4'b%b | Z-Stab[3:0]=4'b%b)", 
                     {sx_in, sz_in}, sx_in, sz_in);
            $display("  Pauli-X Mask[8:0] : 9'b%b (Hex: 9'h%03h)", pauli_x_correction, pauli_x_correction);
            $display("  Pauli-Z Mask[8:0] : 9'b%b (Hex: 9'h%03h)", pauli_z_correction, pauli_z_correction);
            $display("  Cycles Elapsed    : %0d cycles | Latency @ 200MHz: %0d ns", 
                     m_axis_tuser, m_axis_tuser * 5);

            @(posedge aclk);
            m_axis_tready <= 1'b1;
            @(posedge aclk);
            m_axis_tready <= 1'b0;
        end
    endtask

    initial begin
        aresetn       = 1'b0;
        s_axis_tdata  = 8'h00;
        s_axis_tvalid = 1'b0;
        m_axis_tready = 1'b0;

        #20;
        aresetn = 1'b1;
        #15;

        $display("\n===============================================================");
        $display("CSS SURFACE CODE SPLIT X/Z STABILIZER DECODER SIMULATION");
        $display("===============================================================");

        // Test 1: Pure X Bit-Flip on Data Qubit D1 (Triggers Z-stabilizers sz[0] & sz[1] -> 4'b0011)
        inject_syndrome(4'b0000, 4'b0011, "Pure Pauli-X Error on Qubit D1");
        #30;

        // Test 2: Pure Z Phase-Flip on Data Qubit D7 (Triggers X-stabilizers sx[2] & sx[3] -> 4'b1100)
        inject_syndrome(4'b1100, 4'b0000, "Pure Pauli-Z Error on Qubit D7");
        #30;

        // Test 3: Pauli-Y Error (Simultaneous X + Z) on Central Qubit D4 (Triggers both planes -> 4'b1001)
        inject_syndrome(4'b1001, 4'b1001, "Pauli-Y (Mixed X+Z) Error on Center Qubit D4");
        #30;

        // Test 4: Mixed Multi-Qubit Error (X error on D3 + Z error on D5)
        inject_syndrome(4'b1010, 4'b0101, "Simultaneous X Error on D3 + Z Error on D5");
        #50;

        $display("===============================================================\n");
        $finish;
    end

endmodule
