# PS/2 Host Controller

This repository delivers a synthesizable APB4 PS/2 host controller, a device
bus-functional model, formal properties, and freestanding C drivers for one
keyboard or mouse on one physical PS/2 port.

The controller provides filtered asynchronous inputs, open-drain host transmit,
independent RX/TX FIFOs, programmable timing, sticky error reporting, and
maskable interrupts. Keyboard scan-code and mouse packet interpretation remain
in software so protocol policy can evolve without changing RTL.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `rtl/` | APB wrapper, register block, controller, RX/TX engines, and interface |
| `dv/` | Reusable PS/2 device model and self-checking RTL testbench |
| `formal/` | SBY proof harness and configuration |
| `sw/` | Freestanding controller, keyboard, and mouse drivers plus host tests |
| `doc/` | Datasheet, integration contract, verification plan, and release records |
| `config/` | Locked Common revision and standalone CI toolchains |

## Validation

```sh
make doctor
make format-check register-check lint
make test synth formal
```

The RTL simulation acceptance marker is `PS2_TEST_PASS`. Generated files are
written below `build/` and are not source artifacts.

See [the datasheet](doc/datasheet.md), [integration guide](doc/integration.md),
and [verification contract](doc/verification.md) before integrating the IP.
