`timescale 1ns/1ns
// multiflex_rx.v -- multiflex protocol RX engine
//
// samples mfx_rx_in on rising edges of mfx_clk_in when mfx_sync_in=1
// bit packing mirrors multiflex_tx: highest-numbered active lane = MSB
// one-cycle latency between last symbol and rx_valid/rx_byte output
//
// shift-and-insert accumulation:
//   rx_sr is built MSB-first by left-shifting in new lane data each symbol.
//   a single case on {do_partial, lanes_r} drives rx_sr with only constant
//   bit indices, giving ~2 LUT levels on the D path instead of the ~7 LUT
//   bit_pos arithmetic of the previous approach.
//   CE for all rx_sr bits = (rise_tick && mfx_sync_in): trivial.
//
// partial symbol:
//   occurs when lanes_r does not divide 8 evenly (only lanes_r=3 for
//   NUM_LANES<=3).  TX sends 0 on lower invalid lanes; we insert only
//   the top (8-rx_collected) lane bits.  for NUM_LANES<=3 the only
//   partial case is lanes_r=3, bits_left=2 (rx_collected=6).

module multiflex_rx #(
  parameter NUM_LANES = 3
) (
  input  wire                  clk,
  input  wire                  rstn,

  input  wire                  cfg_enable,
  input  wire [4:0]            cfg_lanes,
  input  wire                  clr_rx,

  // wire inputs (from loopback mux or external pins)
  input  wire                  mfx_clk_in,
  input  wire [NUM_LANES-1:0]  mfx_rx_in,
  input  wire                  mfx_sync_in,

  // received byte (valid for one cycle, one cycle after last symbol)
  output reg  [7:0]            rx_byte,
  output reg                   rx_valid,

  // status
  output reg                   rx_locked,    // sync seen at least once
  output reg                   rx_sync_lost  // sync deasserted mid-byte; sticky, cleared by clr_rx
);

  // -------------------------------------------------------------------------
  // active lane count (clamped to [1, NUM_LANES])
  // -------------------------------------------------------------------------
  wire [4:0] lanes = (cfg_lanes == 0)       ? 5'd1 :
                     (cfg_lanes > NUM_LANES) ? NUM_LANES[4:0] :
                     cfg_lanes;

  // lanes_r: registered; isolates the clamping comparators from the
  // rx_sr D mux so only ~2 LUT levels remain on the critical path
  reg [4:0] lanes_r;
  always @(posedge clk) begin
    if (!rstn) lanes_r <= 5'd1;
    else       lanes_r <= lanes;
  end

  // -------------------------------------------------------------------------
  // zero-extend mfx_rx_in to 8 bits so case arms compile cleanly for
  // any NUM_LANES without out-of-range bit selects
  // -------------------------------------------------------------------------
  wire [7:0] rx_in_w = {{(8-NUM_LANES){1'b0}}, mfx_rx_in};

  // -------------------------------------------------------------------------
  // partial-symbol detection (registered inputs only -> fast wire)
  // do_partial: this symbol has fewer valid lane bits than lanes_r
  // only fires when lanes_r doesn't divide 8, e.g. lanes_r=3, rx_collected=6
  // -------------------------------------------------------------------------
  reg  [3:0] rx_collected;
  wire [4:0] bits_left  = 5'd8 - {1'b0, rx_collected};
  wire       do_partial = ({1'b0, lanes_r} > bits_left);

  // -------------------------------------------------------------------------
  // rising edge detect on mfx_clk_in
  // -------------------------------------------------------------------------
  reg mfx_clk_prev;
  always @(posedge clk) begin
    if (!rstn) mfx_clk_prev <= 1'b0;
    else       mfx_clk_prev <= mfx_clk_in;
  end
  wire rise_tick = mfx_clk_in && !mfx_clk_prev;

  // -------------------------------------------------------------------------
  // RX state machine
  // -------------------------------------------------------------------------
  reg [7:0] rx_sr;
  reg       rx_done;

  always @(posedge clk) begin
    rx_valid <= 1'b0;

    if (!rstn || !cfg_enable) begin
      rx_sr        <= 8'd0;
      rx_collected <= 4'd0;
      rx_done      <= 1'b0;
      rx_locked    <= 1'b0;
      rx_sync_lost <= 1'b0;
    end else begin
      if (clr_rx) rx_sync_lost <= 1'b0;

      if (rx_done) begin
        rx_byte  <= rx_sr;
        rx_valid <= 1'b1;
      end
      rx_done <= 1'b0;

      if (rise_tick) begin
        if (!mfx_sync_in) begin
          if (rx_locked && rx_collected != 4'd0) begin
            rx_sync_lost <= 1'b1;
          end
          rx_locked    <= 1'b0;
          rx_collected <= 4'd0;
        end else begin
          rx_locked <= 1'b1;

          // case on {do_partial, lanes_r}: all bit indices are constants so
          // synthesis produces a shallow mux tree with no arithmetic depth.
          // non-partial arms: left-shift rx_sr by lanes_r, insert all lanes.
          // partial arms:     left-shift by bits_left, insert top lanes only.
          // for NUM_LANES<=3 the only reachable partial case is lanes_r=3.
          case ({do_partial, lanes_r[2:0]})
            // non-partial: insert all lanes_r bits into rx_sr LSB
            4'b0_001: rx_sr <= {rx_sr[6:0], rx_in_w[0]};
            4'b0_010: rx_sr <= {rx_sr[5:0], rx_in_w[1], rx_in_w[0]};
            4'b0_011: rx_sr <= {rx_sr[4:0], rx_in_w[2], rx_in_w[1], rx_in_w[0]};
            4'b0_100: rx_sr <= {rx_sr[3:0], rx_in_w[3], rx_in_w[2], rx_in_w[1], rx_in_w[0]};
            4'b0_101: rx_sr <= {rx_sr[2:0], rx_in_w[4], rx_in_w[3], rx_in_w[2], rx_in_w[1], rx_in_w[0]};
            4'b0_110: rx_sr <= {rx_sr[1:0], rx_in_w[5], rx_in_w[4], rx_in_w[3], rx_in_w[2], rx_in_w[1], rx_in_w[0]};
            4'b0_111: rx_sr <= {rx_sr[0],   rx_in_w[6], rx_in_w[5], rx_in_w[4], rx_in_w[3], rx_in_w[2], rx_in_w[1], rx_in_w[0]};
            // partial: lanes_r=3, bits_left=2 (only reachable case for NUM_LANES<=3)
            4'b1_011: rx_sr <= {rx_sr[5:0], rx_in_w[2], rx_in_w[1]};
            // partial: lanes_r=5, bits_left=3 (for NUM_LANES=5)
            4'b1_101: rx_sr <= {rx_sr[4:0], rx_in_w[4], rx_in_w[3], rx_in_w[2]};
            // partial: lanes_r=6, bits_left=2
            4'b1_110: rx_sr <= {rx_sr[5:0], rx_in_w[5], rx_in_w[4]};
            // partial: lanes_r=7, bits_left=1
            4'b1_111: rx_sr <= {rx_sr[6:0], rx_in_w[6]};
            default: rx_sr <= rx_sr;
          endcase

          if ({1'b0, rx_collected} + {1'b0, lanes_r[3:0]} >= 5'd8) begin
            rx_done      <= 1'b1;
            rx_collected <= 4'd0;
          end else begin
            rx_collected <= rx_collected + lanes_r[3:0];
          end
        end
      end
    end
  end

endmodule
