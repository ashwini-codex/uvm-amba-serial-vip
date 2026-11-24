// ----------------------------------------------------------------------------
// apb_spi_master.sv : SPI master with an APB3 register interface (DUT for the SPI bench)
//
// One byte per chip-select, MSB first, all four modes (CPOL/CPHA).
// SCLK half-period = CLKDIV PCLK cycles (use CLKDIV >= 2).
//
// Registers (byte offsets):
//   0x00 CTRL    RW  [0] cpol  [1] cpha
//   0x04 CLKDIV  RW  [7:0] half-period in PCLK cycles, reset 4
//   0x08 TXDATA  W   [7:0] write starts a transfer; ignored while busy
//   0x0C RXDATA  R   [7:0] byte received on MISO  [8] done; reading clears done
//   0x10 STATUS  R   [0] busy  [1] done
// Any other address -> PSLVERR. No wait states.
//
// Bug switches:
//   BUG_SPI_CPOL : SCLK always idles low (ignores CPOL)
//   BUG_SPI_CPHA : MISO always sampled on the leading edge (ignores CPHA)
// ----------------------------------------------------------------------------
`timescale 1ns/1ps

module apb_spi_master (
  input  logic        PCLK,
  input  logic        PRESETn,
  input  logic [31:0] PADDR,
  input  logic        PSEL,
  input  logic        PENABLE,
  input  logic        PWRITE,
  input  logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  output logic        PREADY,
  output logic        PSLVERR,
  output logic        sclk,
  output logic        cs_n,
  output logic        mosi,
  input  logic        miso
);

  localparam logic [11:0] A_CTRL   = 12'h000;
  localparam logic [11:0] A_CLKDIV = 12'h004;
  localparam logic [11:0] A_TXDATA = 12'h008;
  localparam logic [11:0] A_RXDATA = 12'h00C;
  localparam logic [11:0] A_STATUS = 12'h010;

  // ---------------- APB ----------------
  logic        cpol, cpha;
  logic [7:0]  div;
  logic        apb_wr, apb_rd, addr_ok;
  logic [11:0] a;
  logic [7:0]  rx_data;
  logic        busy, done;

  assign a       = PADDR[11:0];
  assign addr_ok = (PADDR[31:12] == '0) &&
                   (a == A_CTRL || a == A_CLKDIV || a == A_TXDATA || a == A_RXDATA || a == A_STATUS);
  assign apb_wr  = PSEL && PENABLE && PWRITE  && addr_ok;
  assign apb_rd  = PSEL && PENABLE && !PWRITE && addr_ok;
  assign PREADY  = 1'b1;
  assign PSLVERR = PSEL && PENABLE && !addr_ok;

  always_comb begin
    PRDATA = 32'h0;
    if (PSEL && !PWRITE) begin
      case (a)
        A_CTRL   : PRDATA = {30'h0, cpha, cpol};
        A_CLKDIV : PRDATA = {24'h0, div};
        A_RXDATA : PRDATA = {23'h0, done, rx_data};
        A_STATUS : PRDATA = {30'h0, done, busy};
        default  : PRDATA = 32'h0;
      endcase
    end
  end

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      cpol <= 1'b0;
      cpha <= 1'b0;
      div  <= 8'd4;
    end
    else if (apb_wr) begin
      case (a)
        A_CTRL   : {cpha, cpol} <= PWDATA[1:0];
        A_CLKDIV : div          <= PWDATA[7:0];
        default  : ;
      endcase
    end
  end

  // ---------------- Shift engine ----------------
  typedef enum logic [1:0] {S_IDLE, S_XFER, S_HOLD} state_e;
  state_e     state;
  logic [7:0] tx_sh, rx_sh, cnt;
  logic [3:0] edge_cnt;          // 0..15
  logic       cpol_q, cpha_q;
  logic       leading, sample_edge;

  assign leading = (edge_cnt[0] == 1'b0);          // edges 0,2,4.. are leading
`ifdef BUG_SPI_CPHA
  assign sample_edge = leading;
`else
  assign sample_edge = cpha_q ? !leading : leading;
`endif

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      state    <= S_IDLE;
      sclk     <= 1'b0;
      cs_n     <= 1'b1;
      mosi     <= 1'b0;
      tx_sh    <= '0;
      rx_sh    <= '0;
      rx_data  <= '0;
      cnt      <= '0;
      edge_cnt <= '0;
      busy     <= 1'b0;
      done     <= 1'b0;
      cpol_q   <= 1'b0;
      cpha_q   <= 1'b0;
    end
    else begin
      if (apb_rd && a == A_RXDATA) done <= 1'b0;

      case (state)
        S_IDLE: begin
`ifdef BUG_SPI_CPOL
          sclk <= 1'b0;
`else
          sclk <= cpol;
`endif
          if (apb_wr && a == A_TXDATA) begin
            cpol_q   <= cpol;
            cpha_q   <= cpha;
            cs_n     <= 1'b0;
            busy     <= 1'b1;
            cnt      <= '0;
            edge_cnt <= '0;
            if (!cpha) begin                 // CPHA=0: first bit out before the first edge
              mosi  <= PWDATA[7];
              tx_sh <= {PWDATA[6:0], 1'b0};
            end
            else begin
              tx_sh <= PWDATA[7:0];
            end
            state <= S_XFER;
          end
        end

        S_XFER: begin
          if (cnt == div - 1'b1) begin
            cnt      <= '0;
            sclk     <= ~sclk;
            edge_cnt <= edge_cnt + 1'b1;
            if (sample_edge) begin
              rx_sh <= {rx_sh[6:0], miso};
            end
            else if (!(cpha_q == 1'b0 && edge_cnt == 4'd15)) begin
              mosi  <= tx_sh[7];
              tx_sh <= {tx_sh[6:0], 1'b0};
            end
            if (edge_cnt == 4'd15) state <= S_HOLD;
          end
          else cnt <= cnt + 1'b1;
        end

        S_HOLD: begin
          if (cnt == div - 1'b1) begin
            cnt     <= '0;
            cs_n    <= 1'b1;
            busy    <= 1'b0;
            done    <= 1'b1;
            rx_data <= rx_sh;
            state   <= S_IDLE;
          end
          else cnt <= cnt + 1'b1;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
