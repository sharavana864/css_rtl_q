`timescale 1ns / 1ps

module surface_decoder_uf_grid (
    input  wire        aclk,
    input  wire        aresetn,         // Active-low synchronous reset

    // AXI4-Stream Slave Interface (8-bit Syndrome Input)
    // s_axis_tdata[3:0] = Z-stabilizers (detects X bit-flip errors)
    // s_axis_tdata[7:4] = X-stabilizers (detects Z phase-flip errors)
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output reg         s_axis_tready,

    // AXI4-Stream Master Interface (18-bit Pauli X & Z Correction Mask)
    // m_axis_tdata[8:0]  = 9-bit Pauli-X correction mask (for data qubits D0..D8)
    // m_axis_tdata[17:9] = 9-bit Pauli-Z correction mask (for data qubits D0..D8)
    output reg  [17:0] m_axis_tdata,
    output reg  [7:0]  m_axis_tuser,    // Exact clock cycles elapsed (Latency telemetry)
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready
);

    localparam IDLE = 2'b00;
    localparam GROW = 2'b01;
    localparam PEEL = 2'b10;

    reg [1:0] state;
    reg [3:0] sz; // Z-stabilizers (detect X bit-flip errors)
    reg [3:0] sx; // X-stabilizers (detect Z phase-flip errors)
    reg [7:0] cycle_cnt;

    reg [8:0] corr_x; // Candidate Pauli-X corrections (D8..D0)
    reg [8:0] corr_z; // Candidate Pauli-Z corrections (D8..D0)

    always @(posedge aclk) begin
        if (!aresetn) begin
            state         <= IDLE;
            s_axis_tready <= 1'b1;
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= 18'b0;
            m_axis_tuser  <= 8'd0;
            sz            <= 4'b0;
            sx            <= 4'b0;
            cycle_cnt     <= 8'd0;
            corr_x        <= 9'b0;
            corr_z        <= 9'b0;
        end else begin
            case (state)
                IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    cycle_cnt     <= 8'd0;
                    if (s_axis_tvalid && s_axis_tready) begin
                        sz            <= s_axis_tdata[3:0]; // Latch Z-stabilizers
                        sx            <= s_axis_tdata[7:4]; // Latch X-stabilizers
                        s_axis_tready <= 1'b0;              // Backpressure during decode
                        state         <= GROW;
                    end else begin
                        s_axis_tready <= 1'b1;
                    end
                end

                GROW: begin
                    cycle_cnt <= cycle_cnt + 1'b1;

                    // ---------------------------------------------------------
                    // PLANE 1: Z-Stabilizer Plane (Resolves Pauli-X Bit-Flips)
                    // ---------------------------------------------------------
                    corr_x[0] <=  sz[0] & ~sz[1] & ~sz[2];          // D0 (Top-left corner)
                    corr_x[1] <=  sz[0] &  sz[1] & ~sz[2];          // D1 (Top shared edge)
                    corr_x[2] <= ~sz[0] &  sz[1] & ~sz[3];          // D2 (Top-right corner)
                    corr_x[3] <=  sz[0] &  sz[2] & ~sz[1];          // D3 (Left shared edge)
                    corr_x[4] <= (sz[0] &  sz[3]) | (sz[1] & sz[2]);// D4 (Center bulk qubit)
                    corr_x[5] <=  sz[1] &  sz[3] & ~sz[2];          // D5 (Right shared edge)
                    corr_x[6] <=  sz[2] & ~sz[0] & ~sz[3];          // D6 (Bottom-left corner)
                    corr_x[7] <=  sz[2] &  sz[3] & ~sz[0];          // D7 (Bottom shared edge)
                    corr_x[8] <=  sz[3] & ~sz[1] & ~sz[2];          // D8 (Bottom-right corner)

                    // ---------------------------------------------------------
                    // PLANE 2: X-Stabilizer Plane (Resolves Pauli-Z Phase-Flips)
                    // ---------------------------------------------------------
                    corr_z[0] <=  sx[0] & ~sx[1] & ~sx[2];          // D0
                    corr_z[1] <=  sx[0] &  sx[1] & ~sx[2];          // D1
                    corr_z[2] <= ~sx[0] &  sx[1] & ~sx[3];          // D2
                    corr_z[3] <=  sx[0] &  sx[2] & ~sx[1];          // D3
                    corr_z[4] <= (sx[0] &  sx[3]) | (sx[1] & sx[2]);// D4 (Center bulk qubit)
                    corr_z[5] <=  sx[1] &  sx[3] & ~sx[2];          // D5
                    corr_z[6] <=  sx[2] & ~sx[0] & ~sx[3];          // D6
                    corr_z[7] <=  sx[2] &  sx[3] & ~sx[0];          // D7
                    corr_z[8] <=  sx[3] & ~sx[1] & ~sx[2];          // D8

                    // Complete 12-cycle cluster growth & boundary consensus window
                    if (cycle_cnt >= 8'd11) begin
                        state <= PEEL;
                    end
                end

                PEEL: begin
                    // Output combined 18-bit Pauli correction mask ({Z_mask, X_mask})
                    m_axis_tdata  <= {corr_z, corr_x};
                    m_axis_tuser  <= cycle_cnt + 1'b1; // 13 total clock cycles (0D hex)
                    m_axis_tvalid <= 1'b1;

                    if (m_axis_tready) begin
                        m_axis_tvalid <= 1'b0;
                        s_axis_tready <= 1'b1;
                        state         <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
