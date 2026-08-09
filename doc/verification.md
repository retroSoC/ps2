# Verification and Release Contract

A release candidate must pass:

```sh
make format-check register-check lint
make test-iverilog test-verilator test-host
make synth formal
```

The RTL testbench uses one resolved open-drain bus and the reusable device model
to exercise strict APB errors, configuration locking, receive data and error
tags, host transmit with ACK and no-ACK, sticky interrupts, FIFO flushes, and
line release on disable. Both simulators must print `PS2_TEST_PASS` and exit
successfully.

Host C tests cover keyboard Set-2 make/break/extended/Pause parsing, mouse
three- and four-byte packet alignment, sign extension, wheel/buttons, and API
argument checks. They do not emulate MMIO command sequencing; RTL simulation
owns that boundary.

Formal runs against the scalar `ps2_reg` below the APB interface wrapper. The
proof checks FIFO bounds, open-drain output values, interrupt equivalence,
disabled line release, always-ready APB behavior, and access-phase error
qualification. Covers require reachable APB errors, host clock inhibition, and
interrupt assertion.

System integration signoff must additionally cover pad electrical behavior,
GPIO mux ownership, interrupt routing, APB address decode, reset sequencing,
and CDC/timing reports. Those properties are outside the standalone proof.
