// ----------------------------------------------------------------------------
// apb_uart.sv : UART with an APB3 register interface (DUT for the UART bench)
//
// Frame: 1 start bit (0), 8 data bits LSB first, optional parity, 1 stop bit (1).
// Bit time = BAUD.div PCLK cycles (use div >= 4).
//
// Registers (byte offsets):
//   0x00 CTRL    RW  [0] parity_en  [1] parity_odd (0 = even)
//   0x04 BAUD    RW  [15:0] div (PCLK cycles per bit), reset 16
//   0x08 TXDATA  W   [7:0] byte to send; ignored while STATUS.tx_busy
//   0x0C RXDATA  R   [7:0] data [8] parity_err [9] frame_err [10] valid
//                    reading clears valid / errors / overrun
//   0x10 STATUS  R   [0] tx_busy [1] rx_valid [2] rx_overrun
// Any other address -> PSLVERR. No wait states.
//
// Bug switches:
//   BUG_UART_PARITY : TX sends the inverted parity bit
//   BUG_UART_RXMSB  : RX drops data bit 7
// ----------------------------------------------------------------------------
`timescale 1ns/1ps

module apb_uart (
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
  output logic        uart_tx,
  input  logic        uart_rx
);

  localparam logic [11:0] A_CTRL   = 12'h000;
  localparam logic [11:0] A_BAUD   = 12'h004;
  localparam logic [11:0] A_TXDATA = 12'h008;
  localparam logic [11:0] A_RXDATA = 12'h00C;
  localparam logic [11:0] A_STATUS = 12'h010;

  // ---------------- APB register interface ----------------
  logic        par_en, par_odd;
  logic [15:0] div;

  logic        apb_wr, apb_rd, addr_ok;
  logic [11:0] a;

  assign a       = PADDR[11:0];
  assign addr_ok = (PADDR[31:12] == '0) &&
                   (a == A_CTRL || a == A_BAUD || a == A_TXDATA || a == A_RXDATA || a == A_STATUS);
  assign apb_wr  = PSEL && PENABLE && PWRITE  && addr_ok;
  assign apb_rd  = PSEL && PENABLE && !PWRITE && addr_ok;
  assign PREADY  = 1'b1;
  assign PSLVERR = PSEL && PENABLE && !addr_ok;

  // RX result registers
  logic [7:0] rx_data;
  logic       rx_valid, rx_perr, rx_ferr, rx_overrun;
  logic       tx_busy;

  always_comb begin
    PRDATA = 32'h0;
    if (PSEL && !PWRITE) begin
      case (a)
        A_CTRL   : PRDATA = {30'h0, par_odd, par_en};
        A_BAUD   : PRDATA = {16'h0, div};
        A_RXDATA : PRDATA = {21'h0, rx_valid, rx_ferr, rx_perr, rx_data};
        A_STATUS : PRDATA = {29'h0, rx_overrun, rx_valid, tx_busy};
        default  : PRDATA = 32'h0;
      endcase
    end
  end

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      par_en  <= 1'b0;
      par_odd <= 1'b0;
      div     <= 16'd16;
    end
    else if (apb_wr) begin
      case (a)
        A_CTRL : {par_odd, par_en} <= PWDATA[1:0];
        A_BAUD : div               <= PWDATA[15:0];
        default: ;
      endcase
    end
  end

  // ---------------- Transmitter ----------------
  logic [10:0] tx_frame;   // shifted out LSB first
  logic [3:0]  tx_bitcnt, tx_nbits;
  logic [15:0] tx_clkcnt;
  logic        tx_par;

`ifdef BUG_UART_PARITY
  assign tx_par = ~((^PWDATA[7:0]) ^ par_odd);
`else
  assign tx_par = (^PWDATA[7:0]) ^ par_odd;
`endif

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      tx_busy   <= 1'b0;
      tx_frame  <= '1;
      tx_bitcnt <= '0;
      tx_nbits  <= 4'd10;
      tx_clkcnt <= '0;
    end
    else if (!tx_busy) begin
      if (apb_wr && a == A_TXDATA) begin
        tx_frame  <= par_en ? {1'b1, tx_par, PWDATA[7:0], 1'b0}
                            : {1'b1, 1'b1,   PWDATA[7:0], 1'b0};
        tx_nbits  <= par_en ? 4'd11 : 4'd10;
        tx_bitcnt <= '0;
        tx_clkcnt <= '0;
        tx_busy   <= 1'b1;
      end
    end
    else begin
      if (tx_clkcnt == div - 1'b1) begin
        tx_clkcnt <= '0;
        tx_frame  <= {1'b1, tx_frame[10:1]};
        if (tx_bitcnt == tx_nbits - 1'b1) tx_busy   <= 1'b0;
        else                              tx_bitcnt <= tx_bitcnt + 1'b1;
      end
      else begin
        tx_clkcnt <= tx_clkcnt + 1'b1;
      end
    end
  end

  assign uart_tx = tx_busy ? tx_frame[0] : 1'b1;

  // ---------------- Receiver ----------------
  typedef enum logic [2:0] {RX_IDLE, RX_START, RX_DATA, RX_PAR, RX_STOP} rx_state_e;
  rx_state_e   rx_state;
  logic        rx_s1, rx_s2, rx_prev;
  logic [15:0] rx_clkcnt;
  logic [2:0]  rx_bitcnt;
  logic [7:0]  rx_shift;
  logic        rx_parbit;
  logic        rx_clr;

  assign rx_clr = apb_rd && (a == A_RXDATA);

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      rx_s1      <= 1'b1;
      rx_s2      <= 1'b1;
      rx_prev    <= 1'b1;
      rx_state   <= RX_IDLE;
      rx_clkcnt  <= '0;
      rx_bitcnt  <= '0;
      rx_shift   <= '0;
      rx_parbit  <= 1'b0;
      rx_data    <= '0;
      rx_valid   <= 1'b0;
      rx_perr    <= 1'b0;
      rx_ferr    <= 1'b0;
      rx_overrun <= 1'b0;
    end
    else begin
      rx_s1   <= uart_rx;
      rx_s2   <= rx_s1;
      rx_prev <= rx_s2;

      if (rx_clr) begin
        rx_valid   <= 1'b0;
        rx_perr    <= 1'b0;
        rx_ferr    <= 1'b0;
        rx_overrun <= 1'b0;
      end

      case (rx_state)
        RX_IDLE: begin
          rx_clkcnt <= '0;
          if (rx_prev && !rx_s2) rx_state <= RX_START;   // falling edge
        end

        RX_START: begin   // wait to the middle of the start bit
          if (rx_clkcnt == (div >> 1) - 1'b1) begin
            rx_clkcnt <= '0;
            rx_bitcnt <= '0;
            rx_state  <= rx_s2 ? RX_IDLE : RX_DATA;       // glitch -> back to idle
          end
          else rx_clkcnt <= rx_clkcnt + 1'b1;
        end

        RX_DATA: begin
          if (rx_clkcnt == div - 1'b1) begin
            rx_clkcnt <= '0;
            rx_shift  <= {rx_s2, rx_shift[7:1]};
            if (rx_bitcnt == 3'd7) rx_state <= par_en ? RX_PAR : RX_STOP;
            else                   rx_bitcnt <= rx_bitcnt + 1'b1;
          end
          else rx_clkcnt <= rx_clkcnt + 1'b1;
        end

        RX_PAR: begin
          if (rx_clkcnt == div - 1'b1) begin
            rx_clkcnt <= '0;
            rx_parbit <= rx_s2;
            rx_state  <= RX_STOP;
          end
          else rx_clkcnt <= rx_clkcnt + 1'b1;
        end

        RX_STOP: begin
          if (rx_clkcnt == div - 1'b1) begin
            rx_clkcnt  <= '0;
`ifdef BUG_UART_RXMSB
            rx_data    <= {1'b0, rx_shift[6:0]};
`else
            rx_data    <= rx_shift;
`endif
            rx_perr    <= par_en && (rx_parbit != ((^rx_shift) ^ par_odd));
            rx_ferr    <= !rx_s2;
            rx_overrun <= rx_valid && !rx_clr;
            rx_valid   <= 1'b1;
            rx_state   <= RX_IDLE;
          end
          else rx_clkcnt <= rx_clkcnt + 1'b1;
        end

        default: rx_state <= RX_IDLE;
      endcase
    end
  end

endmodule
