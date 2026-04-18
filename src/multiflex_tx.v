`timescale 1ns/1ns
// multiflex_tx.v -- multiflex protocol TX engine
// no APB dependency; parameterized by NUM_LANES
//
// wire protocol:
//   data driven on falling edge of mfx_clk, sampled on rising edge
//   mfx_sync=1 marks a valid symbol clock
//   bits packed MSB-first; highest-numbered active lane carries the MSB
//   last partial symbol: upper lanes carry remaining bits, lower lanes = 0

module multiflex_tx #(
  parameter NUM_LANES = 3
) (
  input  wire                  clk,
  input  wire                  rstn,

  // runtime config (from register block)
  input  wire                  cfg_enable,
  input  wire [4:0]            cfg_lanes,   // 1..NUM_LANES active lanes
  input  wire [7:0]            cfg_clk_div, // wire clk half-period in fabric cycles minus 1

  // TX push interface
  input  wire [7:0]            tx_byte,
  input  wire                  tx_wr,
  output wire                  tx_full,
  output wire                  tx_empty,

  // status
  output wire                  tx_busy,

  // wire outputs (pipeline-registered: driven through a one-cycle output stage
  // so that all pad-facing flip-flops are the last register before the pad,
  // eliminating long combinational paths on the TX output)
  output reg                   mfx_clk,
  output reg  [NUM_LANES-1:0]  mfx_tx,
  output reg                   mfx_sync,

  // fabric-side copies: driven by the pre-pipeline (_r) registers, which are
  // pure fabric FFs.  NOT connected to output pads so synthesis will not
  // promote them to the global clock network.  use these for RX loopback and
  // edge-detect feedback.
  //
  // syn_preserve prevents synthesis from merging these with the pad-facing
  // output FFs (mfx_clk/mfx_sync), which would force the RX module to read
  // from a FF placed near the pad, causing long routing across the chip.
  (* syn_preserve = "true" *) output reg                   mfx_clk_fabric,
  (* syn_preserve = "true" *) output reg  [NUM_LANES-1:0]  mfx_tx_fabric,
  (* syn_preserve = "true" *) output reg                   mfx_sync_fabric
);

  // -------------------------------------------------------------------------
  // FIFO -- 16-entry single-clock
  // -------------------------------------------------------------------------
  localparam FDEPTH = 16;
  localparam FBITS  = 4;

  reg [7:0]     fifo [0:FDEPTH-1];
  reg [FBITS:0] wr_ptr;
  reg [FBITS:0] rd_ptr;

  wire fifo_full_w  = (wr_ptr[FBITS] != rd_ptr[FBITS]) &&
                      (wr_ptr[FBITS-1:0] == rd_ptr[FBITS-1:0]);
  wire fifo_empty_w = (wr_ptr == rd_ptr);

  // fifo_full_r: registered version of fifo_full_w.
  // breaks the rd_ptr -> fifo_full_w -> FIFO write CE combinational chain
  // (chain A: 128 RAMREG FFs all seeing fifo_full_w on their CE).
  // conservative: the FIFO appears full for one extra cycle after a read;
  // harmless because the TX FIFO is filled by the drain SM at pclk rate,
  // never back-to-back at fabric-clk rate, so the 1-cycle pessimism is
  // invisible to the caller.
  reg fifo_full_r;
  always @(posedge clk) begin
    if (!rstn || !cfg_enable) fifo_full_r <= 1'b0;
    else                      fifo_full_r <= fifo_full_w;
  end

  assign tx_full  = fifo_full_r;
  assign tx_empty = fifo_empty_w;

  always @(posedge clk) begin
    if (!rstn || !cfg_enable) begin
      wr_ptr <= 0;
    end else if (tx_wr && !fifo_full_r) begin
      fifo[wr_ptr[FBITS-1:0]] <= tx_byte;
      wr_ptr <= wr_ptr + 1;
    end
  end

  // -------------------------------------------------------------------------
  // wire clock divider
  // -------------------------------------------------------------------------
  // mfx_clk is generated with a configurable half-period.
  // data is updated on the fabric posedge that ends the mfx_clk HIGH half
  // (i.e., mfx_clk is about to go LOW), giving the receiver a full low half
  // plus setup time before the next rising sample edge.
  //
  // clock only runs when the FIFO has data or the state machine is active;
  // holds low otherwise so the clock is absent between transmissions

  reg [7:0] div_cnt;
  reg       phase; // 0 = high half in progress, 1 = low half in progress

  // forward declarations needed before wire assignments that reference them
  reg       active;
  reg       drain;

  wire tx_busy_w = active || !fifo_empty_w;

  // drain: set on the last data fall_tick (last bit of last byte, fifo empty)
  // keeps the clock alive through one more full cycle so the receiver can
  // sample the last rising edge with sync=1, then see a clean sync=0 on the
  // trailing falling edge before the clock gates off
  wire clk_run = tx_busy_w || drain;

  // clk_run_r: registered version used only for the divider reset condition.
  // breaks the rd_ptr->fifo_empty_w->clk_run->RESET timing chain (chain B).
  // the divider resets one cycle late when going idle; harmless because the
  // drain state already extends the clock by a full cycle after the last byte.
  reg clk_run_r;
  always @(posedge clk) begin
    if (!rstn || !cfg_enable) clk_run_r <= 1'b0;
    else                      clk_run_r <= clk_run;
  end

  // fall_tick uses clk_run_r (registered) instead of clk_run.
  // breaks the rd_ptr -> fifo_empty_w -> clk_run -> fall_tick -> CE/D chains
  // (paths to mfx_sync_r CE and mfx_tx_r D).
  // effect: first fall_tick after startup is delayed by 1 fabric cycle (harmless;
  // divider is still in reset on cycle N when clk_run first goes high).
  // effect at drain end: one extra idle fall_tick fires after drain clears (harmless;
  // hits the !active branch which drives zeros and is a no-op when fifo is empty).
  wire fall_tick = (div_cnt == 0) && (phase == 1'b0) && cfg_enable && clk_run_r;

  // pre-pipeline internal registers: state machine and divider write these;
  // also driven out as fabric-side copies so the placer can put them near
  // the RX module rather than near the output pads
  reg                  mfx_clk_r;
  reg [7:0]            mfx_tx_r; // always 8 bits; upper (8-NUM_LANES) bits unused
  reg                  mfx_sync_r;
  reg                  mfx_clk_fabric_r;
  reg                  mfx_sync_fabric_r;

  // fabric outputs: driven directly from _r registers so the P&R tool can
  // place them near the RX module.  they are one cycle ahead of the pad-facing
  // outputs; since RX clock/data/sync all shift by the same one cycle the
  // relative phase is preserved and the protocol is unaffected.
  always @(posedge clk) begin
    if (!rstn || !cfg_enable) begin
      mfx_clk_fabric  <= 1'b0;
      mfx_tx_fabric   <= {NUM_LANES{1'b0}};
      mfx_sync_fabric <= 1'b0;
    end else begin
      mfx_clk_fabric  <= mfx_clk_fabric_r;
      mfx_tx_fabric   <= mfx_tx_r[NUM_LANES-1:0];
      mfx_sync_fabric <= mfx_sync_fabric_r;
    end
  end

  // output pipeline register: pad-facing FFs, no reset.
  // neither rstn nor cfg_enable are needed here: the pre-pipeline _r registers
  // are reset by both and will drive 0s into this stage, which propagates to
  // the pads one cycle later.  removing the reset eliminates the long routing
  // path from the APB/reset-sync region to these pad-adjacent FFs.
  always @(posedge clk) begin
    mfx_clk  <= mfx_clk_r;
    mfx_tx   <= mfx_tx_r[NUM_LANES-1:0];
    mfx_sync <= mfx_sync_r;
  end

  always @(posedge clk) begin
    if (!rstn || !cfg_enable || !clk_run_r) begin
      div_cnt          <= 0;
      phase            <= 0;
      mfx_clk_r        <= 0;
      mfx_clk_fabric_r <= 0;
    end else begin
      if (div_cnt == 0) begin
        div_cnt          <= cfg_clk_div;
        phase            <= ~phase;
        mfx_clk_r        <= phase;
        mfx_clk_fabric_r <= phase;
      end else begin
        div_cnt <= div_cnt - 1;
      end
    end
  end

  // -------------------------------------------------------------------------
  // active lane count (clamped to [1, NUM_LANES])
  // -------------------------------------------------------------------------
  wire [4:0] lanes = (cfg_lanes == 0)       ? 5'd1 :
                     (cfg_lanes > NUM_LANES) ? NUM_LANES[4:0] :
                     cfg_lanes;

  // lanes_r: registered; removes clamping comparators from the mfx_tx_r D
  // and sr-shift paths so only ~2 LUT levels remain on those critical paths.
  // safe: cfg_lanes is stable during transfers.
  reg [4:0] lanes_r;
  always @(posedge clk) begin
    if (!rstn || !cfg_enable) lanes_r <= 5'd1;
    else                      lanes_r <= lanes;
  end

  // -------------------------------------------------------------------------
  // TX state machine
  // -------------------------------------------------------------------------
  // States:
  //   IDLE  (!active): wait for a byte in the FIFO
  //   LOAD  (one fall_tick): pop FIFO head into sr, transition to SEND
  //   SEND  (active): on each fall_tick drive one symbol from sr then shift
  //
  // sr holds the current byte, MSB-aligned.
  // rem counts bits remaining (8 down to 1..lanes).
  // Each fall_tick in SEND: drive top `lanes` bits (with zero-pad when
  // rem < lanes), shift sr left by lanes, decrement rem.
  // When rem reaches 0 after the shift, check FIFO for next byte.

  reg [7:0] sr;
  reg [3:0] rem;   // 0 = idle/load, 1..8 = bits left in current byte

  assign tx_busy = active || !fifo_empty_w || drain;

  wire [7:0] fifo_head = fifo[rd_ptr[FBITS-1:0]];

  always @(posedge clk) begin
    if (!rstn || !cfg_enable) begin
      rd_ptr           <= 0;
      sr               <= 0;
      rem              <= 0;
      active           <= 0;
      drain            <= 0;
      mfx_tx_r         <= 0;
      mfx_sync_r       <= 0;
      mfx_sync_fabric_r <= 0;
    end else if (fall_tick) begin
      if (!active) begin
        // drain fall_tick or idle fall_tick: always clear sync/tx
        // if fifo has data, also load it (back-to-back after a drain burst)
        mfx_tx_r          <= 0;
        mfx_sync_r        <= 0;
        mfx_sync_fabric_r <= 0;
        drain             <= 0;
        if (!fifo_empty_w) begin
          sr     <= fifo_head;
          rem    <= 4'd8;
          active <= 1;
          rd_ptr <= rd_ptr + 1;
        end
      end else begin
        // SEND: drive current symbol from sr onto active lanes.
        // case on lanes_r (registered) with constant sr[] indices gives
        // ~2 LUT levels on the mfx_tx_r D path instead of ~7.
        // lane[lanes_r-1] = MSB (sr[7]), lane[0] = LSB of this symbol.
        // lower lanes are zero-padded when rem < lanes_r (partial symbol).
        // inactive lanes (k >= lanes_r) are zeroed by the default assignment
        // below; the active-lane case arms only write the lanes they own.
        mfx_sync_r        <= 1;
        mfx_sync_fabric_r <= 1;
        mfx_tx_r          <= 8'b0;
        case (lanes_r[2:0])
          3'd1: begin
            mfx_tx_r[0] <= sr[7];
          end
          3'd2: begin
            mfx_tx_r[1] <= sr[7];
            mfx_tx_r[0] <= (rem >= 4'd2) ? sr[6] : 1'b0;
          end
          3'd3: begin
            mfx_tx_r[2] <= sr[7];
            mfx_tx_r[1] <= (rem >= 4'd2) ? sr[6] : 1'b0;
            mfx_tx_r[0] <= (rem >= 4'd3) ? sr[5] : 1'b0;
          end
          3'd4: begin
            mfx_tx_r[3] <= sr[7];
            mfx_tx_r[2] <= (rem >= 4'd2) ? sr[6] : 1'b0;
            mfx_tx_r[1] <= (rem >= 4'd3) ? sr[5] : 1'b0;
            mfx_tx_r[0] <= (rem >= 4'd4) ? sr[4] : 1'b0;
          end
          3'd5: begin
            mfx_tx_r[4] <= sr[7];
            mfx_tx_r[3] <= (rem >= 4'd2) ? sr[6] : 1'b0;
            mfx_tx_r[2] <= (rem >= 4'd3) ? sr[5] : 1'b0;
            mfx_tx_r[1] <= (rem >= 4'd4) ? sr[4] : 1'b0;
            mfx_tx_r[0] <= (rem >= 4'd5) ? sr[3] : 1'b0;
          end
          3'd6: begin
            mfx_tx_r[5] <= sr[7];
            mfx_tx_r[4] <= (rem >= 4'd2) ? sr[6] : 1'b0;
            mfx_tx_r[3] <= (rem >= 4'd3) ? sr[5] : 1'b0;
            mfx_tx_r[2] <= (rem >= 4'd4) ? sr[4] : 1'b0;
            mfx_tx_r[1] <= (rem >= 4'd5) ? sr[3] : 1'b0;
            mfx_tx_r[0] <= (rem >= 4'd6) ? sr[2] : 1'b0;
          end
          3'd7: begin
            mfx_tx_r[6] <= sr[7];
            mfx_tx_r[5] <= (rem >= 4'd2) ? sr[6] : 1'b0;
            mfx_tx_r[4] <= (rem >= 4'd3) ? sr[5] : 1'b0;
            mfx_tx_r[3] <= (rem >= 4'd4) ? sr[4] : 1'b0;
            mfx_tx_r[2] <= (rem >= 4'd5) ? sr[3] : 1'b0;
            mfx_tx_r[1] <= (rem >= 4'd6) ? sr[2] : 1'b0;
            mfx_tx_r[0] <= (rem >= 4'd7) ? sr[1] : 1'b0;
          end
          default: begin
            mfx_tx_r[0] <= sr[7];
          end
        endcase

        if (rem <= {1'b0, lanes_r[3:0]}) begin
          // last symbol of this byte
          if (!fifo_empty_w) begin
            // back-to-back: load next byte; first symbol on next fall_tick
            sr     <= fifo_head;
            rem    <= 4'd8;
            rd_ptr <= rd_ptr + 1;
            // active stays 1, mfx_sync_r stays 1 for this symbol
            // next fall_tick will drive the first symbol of the new byte
          end else begin
            // no more data; arm drain so the clock runs one more cycle
            // -- the receiver samples this symbol's rising edge (sync=1),
            //    then sees a clean sync=0 falling edge before clock stops
            active <= 0;
            rem    <= 0;
            drain  <= 1;
          end
        end else begin
          // shift sr left by lanes_r: constant-index case avoids barrel shifter
          case (lanes_r[2:0])
            3'd1: sr <= {sr[6:0], 1'b0};
            3'd2: sr <= {sr[5:0], 2'b0};
            3'd3: sr <= {sr[4:0], 3'b0};
            3'd4: sr <= {sr[3:0], 4'b0};
            3'd5: sr <= {sr[2:0], 5'b0};
            3'd6: sr <= {sr[1:0], 6'b0};
            3'd7: sr <= {sr[0],   7'b0};
            default: sr <= {sr[6:0], 1'b0};
          endcase
          rem <= rem - lanes_r[3:0];
        end
      end
    end else begin
      // no fall_tick: clear outputs when truly idle (not during drain)
      // drain holds sync_r=1 so the receiver can still sample the last rising edge
      if (!active && fifo_empty_w && !drain) begin
        mfx_tx_r          <= 0;
        mfx_sync_r        <= 0;
        mfx_sync_fabric_r <= 0;
      end
    end
  end

endmodule
