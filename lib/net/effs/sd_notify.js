// No systemd on the JS lane.
function sd_notify(msg) {
  return { $: "Unit" };
}

io_eff(CID(Sd.notify), sd_notify);
