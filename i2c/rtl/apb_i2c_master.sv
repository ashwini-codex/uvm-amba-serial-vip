// ----------------------------------------------------------------------------
// apb_i2c_master.sv : byte-level I2C master with an APB3 register interface
// (DUT for the I2C bench).
//
// Software issues one command at a time (START, STOP, WRITE byte, READ byte)
// and polls STATUS.busy. SCL and SDA are open-drain: *_oe = 1 pulls the line
// low, 0 releases it (pull-ups in the testbench). Supports clock stretching:
// after releasing SCL the master waits until the line is really high.
//
// Each bit cell is 4 quarters of (CLKDIV + 2) PCLK cycles (q1 longer if stretched):
//   q0 SCL low  - set SDA        q1 release SCL (wait if stretched)
//   q2 SCL high - sample SDA     q3 pull SCL low
// START: SDA falls in q2; STOP: SDA rises in q2 and SCL stays released.
//
// Registers (byte offsets):
//   0x00 CLKDIV  RW [7:0] quarter-period - 2 (reset 4)
//   0x04 CMD     W  [0] START [1] STOP [2] WRITE [3] READ [4] NACK (for READ)
//                   one command per write, priority START > STOP > WRITE > READ;
//                   ignored while busy
//   0x08 TXDATA  RW [7:0] byte for WRITE
//   0x0C RXDATA  R  [7:0] byte from last READ
//   0x10 STATUS  R  [0] busy [1] rx_ack (1 = NACK received after WRITE)
//                   [2] bus_active (between START and STOP)
// Any other address -> PSLVERR. No wait states.
//
// Bug switches:
//   BUG_I2C_ACK   : STATUS.rx_ack reports the inverted ACK bit
//   BUG_I2C_RDLSB : RXDATA bit 0 is always 0
// ----------------------------------------------------------------------------
`timescale 1ns/1ps

module apb_i2c_master (
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
  output logic        scl_oe,
  output logic        sda_oe,
  input  logic        scl_i,
  input  logic        sda_i
);

  localparam logic [11:0] A_CLKDIV = 12'h000;
  localparam logic [11:0] A_CMD    = 12'h004;
  localparam logic [11:0] A_TXDATA = 12'h008;
  localparam logic [11:0] A_RXDATA = 12'h00C;
  localparam logic [11:0] A_STATUS = 12'h010;

  typedef enum logic [2:0] {C_NONE, C_START, C_STOP, C_WRITE, C_READ} cmd_e;

  // ---------------- APB ----------------
  logic [7:0]  div, txdata, rxdata;
  logic        busy, rx_ack, bus_active;
  logic        apb_wr, addr_ok;
  logic [11:0] a;

  assign a       = PADDR[11:0];
  assign addr_ok = (PADDR[31:12] == '0) &&
                   (a == A_CLKDIV || a == A_CMD || a == A_TXDATA || a == A_RXDATA || a == A_STATUS);
  assign apb_wr  = PSEL && PENABLE && PWRITE && addr_ok;
  assign PREADY  = 1'b1;
  assign PSLVERR = PSEL && PENABLE && !addr_ok;

  always_comb begin
    PRDATA = 32'h0;
    if (PSEL && !PWRITE) begin
      case (a)
        A_CLKDIV : PRDATA = {24'h0, div};
        A_TXDATA : PRDATA = {24'h0, txdata};
        A_RXDATA : PRDATA = {24'h0, rxdata};
        A_STATUS : PRDATA = {29'h0, bus_active, rx_ack, busy};
        default  : PRDATA = 32'h0;
      endcase
    end
  end

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      div    <= 8'd4;
      txdata <= 8'h00;
    end
    else if (apb_wr) begin
      case (a)
        A_CLKDIV : div    <= PWDATA[7:0];
        A_TXDATA : txdata <= PWDATA[7:0];
        default  : ;
      endcase
    end
  end

  // ---------------- Bit engine ----------------
  cmd_e       cmd;
  logic [3:0] bit_idx;       // 0..7 data bits, 8 = ACK bit
  logic [1:0] q;
  logic [7:0] cnt;
  logic       enter;      // perform the entry action of (bit_idx, q) this cycle
  logic       scl_o, sda_o;   // 1 = released
  logic [7:0] tx_sh, rx_sh;
  logic       nack_q;
  logic       q0_sda;

  assign scl_oe = !scl_o;
  assign sda_oe = !sda_o;

  // SDA value to put out at the start of q0
  always_comb begin
    case (cmd)
      C_START : q0_sda = 1'b1;
      C_STOP  : q0_sda = 1'b0;
      C_WRITE : q0_sda = (bit_idx < 8) ? tx_sh[7 - bit_idx[2:0]] : 1'b1;   // release for ACK
      C_READ  : q0_sda = (bit_idx < 8) ? 1'b1 : nack_q;                  // drive ACK/NACK
      default : q0_sda = 1'b1;
    endcase
  end

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      cmd        <= C_NONE;
      busy       <= 1'b0;
      bit_idx       <= '0;
      q          <= '0;
      cnt        <= '0;
      enter      <= 1'b0;
      scl_o      <= 1'b1;
      sda_o      <= 1'b1;
      tx_sh      <= '0;
      rx_sh      <= '0;
      rxdata     <= '0;
      rx_ack     <= 1'b0;
      nack_q     <= 1'b0;
      bus_active <= 1'b0;
    end
    else if (!busy) begin
      if (apb_wr && a == A_CMD) begin
        if      (PWDATA[0]) cmd <= C_START;
        else if (PWDATA[1]) cmd <= C_STOP;
        else if (PWDATA[2]) cmd <= C_WRITE;
        else if (PWDATA[3]) cmd <= C_READ;
        if (|PWDATA[3:0]) begin
          busy   <= 1'b1;
          bit_idx   <= '0;
          q      <= '0;
          enter  <= 1'b1;
          tx_sh  <= txdata;
          nack_q <= PWDATA[4];
        end
      end
    end
    else if (enter) begin
      enter <= 1'b0;
      cnt   <= '0;
      case (q)
        2'd0: sda_o <= q0_sda;
        2'd1: scl_o <= 1'b1;
        2'd2: begin
          case (cmd)
            C_START: sda_o <= 1'b0;                         // START: SDA falls, SCL high
            C_STOP : sda_o <= 1'b1;                         // STOP : SDA rises, SCL high
            C_WRITE: if (bit_idx == 8)
`ifdef BUG_I2C_ACK
                       rx_ack <= !sda_i;
`else
                       rx_ack <= sda_i;
`endif
            C_READ : if (bit_idx < 8) rx_sh <= {rx_sh[6:0], sda_i};
            default: ;
          endcase
        end
        2'd3: if (cmd != C_STOP) scl_o <= 1'b0;
      endcase
    end
    else if (q == 2'd1 && !scl_i) begin
      cnt <= '0;                                            // slave is stretching SCL
    end
    else if (cnt == div) begin
      if (q != 2'd3) begin
        q     <= q + 1'b1;
        enter <= 1'b1;
      end
      else if ((cmd == C_WRITE || cmd == C_READ) && bit_idx != 4'd8) begin
        bit_idx  <= bit_idx + 1'b1;
        q     <= 2'd0;
        enter <= 1'b1;
      end
      else begin
        busy <= 1'b0;
        case (cmd)
          C_START: bus_active <= 1'b1;
          C_STOP : bus_active <= 1'b0;
`ifdef BUG_I2C_RDLSB
          C_READ : rxdata <= {rx_sh[7:1], 1'b0};
`else
          C_READ : rxdata <= rx_sh;
`endif
          default: ;
        endcase
      end
    end
    else begin
      cnt <= cnt + 1'b1;
    end
  end

endmodule
