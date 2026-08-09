# Changelog

## 2.0.0 - 2026-08-09

- Replaced the receive-only keyboard controller with a bidirectional PS/2 host.
- Added RX/TX FIFOs, filtering, programmable timing, errors, and interrupts.
- Added keyboard and mouse freestanding software, a device model, RTL/C tests,
  synthesis, formal verification, and reproducible CI.
- Removed the former APB and AXI compatibility implementations and legacy ABI.
