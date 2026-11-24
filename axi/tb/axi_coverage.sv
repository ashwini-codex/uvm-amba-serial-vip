// ============================================================================
// axi_coverage.sv  --  functional coverage subscriber
//
//   cg_burst  : burst type x len bucket x size (cross)
//   cg_addr   : read/write x address range (low / mid / high / out-of-range)
//   cg_resp   : read/write x response (OKAY / SLVERR)
//   cg_wstrb  : per write beat, WSTRB pattern (full / partial / none) x size
//   cg_hs     : per channel, VALID-to-READY wait bucket (AW, W, B, AR, R)
// ============================================================================
class axi_coverage extends uvm_subscriber #(axi_seq_item);

  `uvm_component_utils(axi_coverage)

  // sampled values
  axi_seq_item    tr;
  axi_resp_e      s_resp;
  axi_strb_kind_e s_kind;
  bit [2:0]       s_size;
  axi_chan_e      h_ch;
  int unsigned    h_wait;

  covergroup cg_burst;
    option.per_instance = 1;
    cp_burst: coverpoint tr.burst {
      bins fixed = {AXI_FIXED};
      bins incr  = {AXI_INCR};
      bins wrap  = {AXI_WRAP};
    }
    cp_len: coverpoint tr.len {
      bins len_1     = {0};
      bins len_2_4   = {[1:3]};
      bins len_5_8   = {[4:7]};
      bins len_9_16  = {[8:15]};
    }
    cp_size: coverpoint tr.size {
      bins b1 = {0};
      bins b2 = {1};
      bins b4 = {2};
    }
    x_burst_len_size: cross cp_burst, cp_len, cp_size {
      ignore_bins wrap_single = binsof(cp_burst.wrap) && binsof(cp_len.len_1);
    }
  endgroup

  covergroup cg_addr;
    option.per_instance = 1;
    cp_rw: coverpoint tr.rw {
      bins rd = {AXI_READ};
      bins wr = {AXI_WRITE};
    }
    cp_range: coverpoint tr.addr {
      bins low  = {[0:1023]};
      bins mid  = {[1024:3071]};
      bins high = {[3072:4095]};
      bins oor  = {[4096:$]};
    }
    x_rw_range: cross cp_rw, cp_range;
  endgroup

  covergroup cg_resp;
    option.per_instance = 1;
    cp_rw: coverpoint tr.rw {
      bins rd = {AXI_READ};
      bins wr = {AXI_WRITE};
    }
    cp_resp: coverpoint s_resp {
      bins okay   = {AXI_OKAY};
      bins slverr = {AXI_SLVERR};
      illegal_bins bad_resp = {AXI_EXOKAY, AXI_DECERR};
    }
    x_rw_resp: cross cp_rw, cp_resp;
  endgroup

  covergroup cg_wstrb;
    option.per_instance = 1;
    cp_kind: coverpoint s_kind {
      bins full    = {STRB_K_FULL};
      bins partial = {STRB_K_PARTIAL};
      bins none    = {STRB_K_NONE};
    }
    cp_size: coverpoint s_size {
      bins b1 = {0};
      bins b2 = {1};
      bins b4 = {2};
    }
    // a 1-byte beat has a single lane: it is either full or none
    x_kind_size: cross cp_kind, cp_size {
      ignore_bins partial_1b = binsof(cp_kind.partial) && binsof(cp_size.b1);
    }
  endgroup

  covergroup cg_hs;
    option.per_instance = 1;
    cp_ch: coverpoint h_ch {
      bins aw = {CH_AW};
      bins w  = {CH_W};
      bins b  = {CH_B};
      bins ar = {CH_AR};
      bins r  = {CH_R};
    }
    cp_wait: coverpoint h_wait {
      bins zero      = {0};
      bins one       = {1};
      bins two_three = {[2:3]};
      bins four_plus = {[4:$]};
    }
    x_ch_wait: cross cp_ch, cp_wait;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_burst = new();
    cg_addr  = new();
    cg_resp  = new();
    cg_wstrb = new();
    cg_hs    = new();
  endfunction

  function void write(axi_seq_item t);
    bit [3:0] m, s;
    tr = t;
    cg_burst.sample();
    cg_addr.sample();

    // transaction response: SLVERR if any beat was SLVERR
    if (t.rw == AXI_WRITE) s_resp = t.bresp;
    else begin
      s_resp = AXI_OKAY;
      foreach (t.rresp[i]) if (t.rresp[i] != AXI_OKAY) s_resp = t.rresp[i];
    end
    cg_resp.sample();

    if (t.rw == AXI_WRITE) begin
      // WSTRB pattern of every beat, relative to the lanes that beat owns
      s_size = t.size;
      foreach (t.strb[i]) begin
        m = axi_lane_mask(axi_beat_addr(t.addr, t.size, t.len, t.burst, i), t.size);
        s = t.strb[i] & m;
        if (s == 4'h0)    s_kind = STRB_K_NONE;
        else if (s == m)  s_kind = STRB_K_FULL;
        else              s_kind = STRB_K_PARTIAL;
        cg_wstrb.sample();
      end
      sample_hs(CH_AW, t.addr_wait);
      foreach (t.data_wait[i]) sample_hs(CH_W, t.data_wait[i]);
      sample_hs(CH_B, t.resp_wait);
    end else begin
      sample_hs(CH_AR, t.addr_wait);
      foreach (t.data_wait[i]) sample_hs(CH_R, t.data_wait[i]);
    end
  endfunction

  function void sample_hs(axi_chan_e ch, int unsigned w);
    h_ch   = ch;
    h_wait = w;
    cg_hs.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    string s;
    s = "\n---------------- AXI functional coverage ----------------";
    s = {s, $sformatf("\n  cg_burst (burst x len x size) : %6.2f%%", cg_burst.get_inst_coverage())};
    s = {s, $sformatf("\n  cg_addr  (rw x addr range)    : %6.2f%%", cg_addr.get_inst_coverage())};
    s = {s, $sformatf("\n  cg_resp  (rw x resp)          : %6.2f%%", cg_resp.get_inst_coverage())};
    s = {s, $sformatf("\n  cg_wstrb (strobe x size)      : %6.2f%%", cg_wstrb.get_inst_coverage())};
    s = {s, $sformatf("\n  cg_hs    (channel x wait)     : %6.2f%%", cg_hs.get_inst_coverage())};
    s = {s, "\n---------------------------------------------------------"};
    `uvm_info("COV", s, UVM_NONE)
  endfunction

endclass
