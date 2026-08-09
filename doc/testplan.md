# Verification Test Plan

| Requirement | Dynamic check | Formal/static check |
| --- | --- | --- |
| Strict APB access policy | Misaligned, unmapped, RO write | Error only in APB access phase |
| RX frame transport | Valid and parity-failed frames | RX FIFO bound |
| Host transmit | ACK and no-ACK command frames | Output data is always zero/open drain |
| FIFO policy | Empty read, flush, levels | RX/TX levels never exceed depth |
| Configuration safety | Reject timing change while enabled | Disabled output-enable is zero |
| Interrupts | Error assertion and RW1C clear | IRQ equals enabled sticky state |
| Keyboard software | Set-2 make/break/E0/E1 | Compiler warnings are errors |
| Mouse software | 3/4-byte packets, sign, wheel, buttons | Compiler warnings are errors |
| Implementation | Simulator elaboration | Verilator lint and Yosys check |

Planned integration-level extensions are randomized clock/data jitter, device
clock stretching, back-to-back FIFO saturation, command resend/error sequences,
and gate-level pad-cell simulations in the consuming SoC.
