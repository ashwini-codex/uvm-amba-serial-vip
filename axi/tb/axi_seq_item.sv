// ============================================================================
// axi_seq_item.sv  --  one complete AXI4 read or write burst
//
// Request fields are randomized by sequences. Response fields and the
// handshake wait counts are filled in by the monitor (and by the driver for
// the request object it drives).
// ============================================================================
class axi_seq_item extends uvm_sequence_item;

  // ---------------- request ----------------
  rand axi_rw_e         rw;
  rand bit [3:0]        id;
  rand bit [31:0]       addr;
  rand bit [7:0]        len;          // beats - 1
  rand bit [2:0]        size;         // bytes per beat = 1 << size
  rand axi_burst_e      burst;
  rand bit [31:0]       data[];       // write data, one word per beat
  rand axi_strb_mode_e  strb_mode;
  rand bit [3:0]        strb_rand[];  // raw random strobes (masked in post_randomize)
       bit [3:0]        strb[];       // WSTRB per beat, derived in post_randomize
  rand bit              addr_err;     // 1: address outside the 4 KB memory

  // master-side delays (cycles)
  rand int unsigned     addr_delay;   // before AWVALID / ARVALID
  rand int unsigned     data_delay[]; // before each WVALID beat / each RREADY beat
  rand int unsigned     resp_delay;   // before BREADY
       bit              zero_delay;   // knob: force every delay to 0

  // ---------------- response ----------------
  axi_resp_e            bresp;
  bit [3:0]             bid;
  axi_resp_e            rresp[];
  bit [3:0]             rid[];

  // ---------------- observed handshake waits (cycles VALID && !READY) -------
  int unsigned          addr_wait;    // AW or AR
  int unsigned          data_wait[];  // per W or R beat
  int unsigned          resp_wait;    // B

  // ---------------- constraints ----------------
  constraint c_size   { size inside {[0:2]}; }
  constraint c_len    { len <= 15; }

  constraint c_arrays {
    data.size()       == len + 1;
    strb_rand.size()  == len + 1;
    data_delay.size() == len + 1;
  }

  // WRAP: len 2/4/8/16 beats, start address aligned to the transfer size
  constraint c_wrap {
    (burst == AXI_WRAP) -> (len inside {1, 3, 7, 15});
    (burst == AXI_WRAP && size == 1) -> (addr[0]   == 1'b0);
    (burst == AXI_WRAP && size == 2) -> (addr[1:0] == 2'b00);
  }

  // INCR must not cross a 4 KB boundary (FIXED and WRAP never can)
  constraint c_4k {
    (burst == AXI_INCR && size == 0) -> ( addr[11:0]           + (len + 1)     <= 4096);
    (burst == AXI_INCR && size == 1) -> ({addr[11:1], 1'b0}    + (len + 1) * 2 <= 4096);
    (burst == AXI_INCR && size == 2) -> ({addr[11:2], 2'b00}   + (len + 1) * 4 <= 4096);
  }

  // in-range by default; sequences override addr_err for error traffic
  constraint c_range {
    soft addr_err == 1'b0;
    (addr_err == 1'b0) -> (addr <  AXI_MEM_BYTES);
    (addr_err == 1'b1) -> (addr >= AXI_MEM_BYTES);
  }

  constraint c_strb_mode {
    strb_mode dist {STRB_FULL := 60, STRB_RANDOM := 35, STRB_NONE := 5};
  }

  constraint c_delay {
    if (zero_delay) {
      addr_delay == 0;
      resp_delay == 0;
      foreach (data_delay[i]) data_delay[i] == 0;
    } else {
      addr_delay dist {0 := 60, [1:3] :/ 30, [4:8] :/ 10};
      resp_delay dist {0 := 60, [1:3] :/ 30, [4:8] :/ 10};
      foreach (data_delay[i]) data_delay[i] dist {0 := 60, [1:3] :/ 30, [4:8] :/ 10};
    }
  }

  `uvm_object_utils(axi_seq_item)

  function new(string name = "axi_seq_item");
    super.new(name);
  endfunction

  // Only lanes that belong to each beat may be strobed.
  function void post_randomize();
    bit [3:0] m;
    strb = new[len + 1];
    foreach (strb[i]) begin
      m = axi_lane_mask(axi_beat_addr(addr, size, len, burst, i), size);
      case (strb_mode)
        STRB_FULL  : strb[i] = m;
        STRB_RANDOM: strb[i] = strb_rand[i] & m;
        default    : strb[i] = 4'h0;
      endcase
    end
  endfunction

  function int unsigned num_beats();
    return len + 1;
  endfunction

  virtual function void do_copy(uvm_object rhs);
    axi_seq_item t;
    super.do_copy(rhs);
    if (!$cast(t, rhs)) `uvm_fatal("CAST", "do_copy: rhs is not an axi_seq_item")
    rw         = t.rw;
    id         = t.id;
    addr       = t.addr;
    len        = t.len;
    size       = t.size;
    burst      = t.burst;
    data       = t.data;
    strb_mode  = t.strb_mode;
    strb_rand  = t.strb_rand;
    strb       = t.strb;
    addr_err   = t.addr_err;
    addr_delay = t.addr_delay;
    data_delay = t.data_delay;
    resp_delay = t.resp_delay;
    zero_delay = t.zero_delay;
    bresp      = t.bresp;
    bid        = t.bid;
    rresp      = t.rresp;
    rid        = t.rid;
    addr_wait  = t.addr_wait;
    data_wait  = t.data_wait;
    resp_wait  = t.resp_wait;
  endfunction

  virtual function string convert2string();
    string s;
    s = $sformatf("%s id=%0h addr=0x%08h len=%0d size=%0dB burst=%s",
                  rw.name(), id, addr, len, (1 << size), burst.name());
    if (rw == AXI_WRITE) begin
      s = {s, $sformatf(" bresp=%s bid=%0h", bresp.name(), bid)};
      foreach (data[i])
        if (i < strb.size())
          s = {s, $sformatf("\n    W[%0d] data=0x%08h strb=%04b", i, data[i], strb[i])};
    end else begin
      foreach (data[i]) begin
        s = {s, $sformatf("\n    R[%0d] data=0x%08h", i, data[i])};
        if (i < rresp.size()) s = {s, $sformatf(" resp=%s", rresp[i].name())};
      end
    end
    return s;
  endfunction

endclass
