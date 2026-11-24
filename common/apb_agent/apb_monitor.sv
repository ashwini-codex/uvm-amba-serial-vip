// ----------------------------------------------------------------------------
// apb_monitor.sv : passive APB monitor. Publishes one item per completed
// transfer (PSEL && PENABLE && PREADY) with wait-state and idle-gap counts.
// ----------------------------------------------------------------------------
class apb_monitor extends uvm_monitor;

  `uvm_component_utils(apb_monitor)

  virtual apb_if                    vif;
  uvm_analysis_port #(apb_seq_item) ap;

  int unsigned n_seen;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    apb_seq_item tr;
    int unsigned waits = 0;
    int unsigned gap   = 0;

    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.PRESETn !== 1'b1) begin
        waits = 0;
        gap   = 0;
        continue;
      end

      if (!vif.mon_cb.PSEL) begin
        gap++;
      end
      else if (vif.mon_cb.PENABLE) begin
        if (vif.mon_cb.PREADY) begin
          tr = apb_seq_item::type_id::create("tr");
          tr.addr        = vif.mon_cb.PADDR;
          tr.write       = vif.mon_cb.PWRITE;
          tr.data        = vif.mon_cb.PWRITE ? vif.mon_cb.PWDATA : vif.mon_cb.PRDATA;
          tr.slverr      = vif.mon_cb.PSLVERR;
          tr.wait_states = waits;
          tr.idle_gap    = gap;
          n_seen++;
          `uvm_info("APB_MON", tr.convert2string(), UVM_HIGH)
          ap.write(tr);
          waits = 0;
          gap   = 0;
        end
        else begin
          waits++;
        end
      end
    end
  endtask

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("APB_MON", $sformatf("observed %0d APB transfers", n_seen), UVM_LOW)
  endfunction

endclass
