# PS/2 Host Controller ABI V2 Datasheet

## Scope

The IP controls one bidirectional PS/2 port connected to either a keyboard or a
mouse. Hardware implements transport: input synchronization/filtering, 11-bit
frame receive, host-to-device transmit, FIFO buffering, timeout supervision,
error capture, and interrupts. Software implements device discovery, command
retry, keyboard scan-code parsing, and mouse packet parsing.

This partition follows the functionality exposed by commercial PS/2 controller
IP: Intel's PS/2 core exposes receive data availability and interrupt-driven
software service, while AMD's XPS PS2 supports bidirectional keyboard/mouse
operation and reports receive, transmit, timeout, and parity failures. ABI V2
uses an explicit FIFO/error model and does not preserve the former receive-only
register ABI.

## Interfaces

| Port | Direction | Description |
| --- | --- | --- |
| `apb4` | APB4 slave | 32-bit control/status interface |
| `ps2_clk_i`, `ps2_dat_i` | input | Pad values after open-drain resolution |
| `ps2_clk_o`, `ps2_dat_o` | output | Constant zero; data value presented to the pad cell |
| `ps2_clk_oe_o`, `ps2_dat_oe_o` | output | Drive-low enables; zero releases the open-drain line |
| `irq_o` | output | OR of enabled sticky interrupt state bits |

The two pad inputs are asynchronous. `ps2_filter` applies a two-stage Common
`cdc_sync` followed by independently qualified stable-value filters. The pad
integration must provide pull-ups and must never interpret output-enable as a
push-pull high drive.

## Configuration

`PCLK_HZ` defines reset timing values. `RX_FIFO_DEPTH` and `TX_FIFO_DEPTH` are
power-of-two values from 2 through 256; both default to 16. Reset defaults are a
three-cycle input filter, 120 us host clock inhibit, 2 ms frame timeout, RX
watermark one, and TX watermark zero.

Timing and watermark registers can be modified only while `CTRL.ENABLE` is
zero. This prevents partially applied configurations during a frame.

## Register Map

All registers are 32-bit and naturally aligned. `PREADY` is always high.
Unaligned, unmapped, wrong-direction, reserved-bit, illegal configuration, or
TX-full accesses assert `PSLVERR` during the APB access phase. Reading an empty
RX FIFO is legal and returns zero with `RXDATA.VALID=0`.

| Offset | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x000` | `CTRL` | RW | Bit 0 enables the controller |
| `0x004` | `STATUS` | RO | Activity, FIFO, filtered-line, drive, and configuration state |
| `0x008` | `RXDATA` | RO/pop | Data, per-frame error tag, valid flag, and pre-pop RX level |
| `0x00C` | `TXDATA` | WO/push | One host-to-device byte |
| `0x010` | `FIFO_STATUS` | RO | RX/TX levels and implemented depths |
| `0x014` | `FIFO_CTRL` | WO | Bits 0/1 flush RX/TX FIFO |
| `0x018` | `RX_WATERMARK` | RW | RX interrupt threshold, range 1 through RX depth |
| `0x01C` | `TX_WATERMARK` | RW | TX interrupt threshold, range 0 through TX depth |
| `0x020` | `FILTER` | RW | Stable input samples, range 1 through 15 |
| `0x024` | `INHIBIT_CYCLES` | RW | Host request-to-send inhibit duration |
| `0x028` | `FRAME_TIMEOUT` | RW | Receive/transmit/bus-stuck timeout |
| `0x02C` | `COMMAND` | WO | Bit 0 aborts TX; bit 1 performs controller soft reset |
| `0x030` | `ERROR_STATUS` | RW1C | Sticky error causes |
| `0x034` | `INTR_STATE` | RW1C | Sticky interrupt causes |
| `0x038` | `INTR_ENABLE` | RW | Interrupt mask |
| `0x03C` | `INTR_TEST` | WO | Sets selected interrupt-state bits for software test |
| `0x0F4` | `IP_ID` | RO | `0x50533232` (`PS22`) |
| `0x0F8` | `IP_VERSION` | RO | `0x00020000` |
| `0x0FC` | `CAPABILITY` | RO | ABI, FIFO depths, and feature bitmap |

`STATUS[0]` is enable, bit 1 bus idle, bits 2/3 RX/TX active, bits 4/5 RX
empty/full, bits 6/7 TX empty/full, bits 8/9 filtered clock/data, bits 10/11
clock/data drive-low, and bit 12 configuration valid.

`RXDATA[7:0]` is data. Bits 10:8 tag start, parity, and stop errors. Bit 15 is
valid and bits 23:16 contain the FIFO level before the read pop.

`ERROR_STATUS[8:0]` reports RX start, parity, stop, timeout, overflow; TX
timeout, no-ACK, aborted; and bus-stuck errors. `INTR_STATE[5:0]` reports RX
watermark, TX watermark, TX done, RX error, TX error, and bus error.

`CAPABILITY[31:24]` is ABI 2, bits 23:16 are RX depth, bits 15:8 are TX depth,
and bits 7:0 are feature flags. The V2 feature value `0x3F` declares RX FIFO,
TX FIFO, host transmit, strict APB errors, programmable filtering/timing, and
keyboard/mouse software support.

## Frame Behavior

Receive samples the PS/2 data line on filtered falling clock edges. The start,
eight LSB-first data bits, odd parity, and stop bit are captured as one FIFO
entry even when a frame error is present. This preserves diagnostic context.

Transmit waits for both lines idle, inhibits clock, asserts data low, releases
clock, shifts the byte and odd parity under device-generated clock edges, then
samples the device ACK bit. Disable, soft reset, abort, and timeout release both
lines. A full TX FIFO rejects a push through `PSLVERR` rather than silently
dropping a command.

## Software Model

The controller API uses caller-provided base addresses and bounded polling.
`ps2_command` retries the standard `0xFE` RESEND response up to three times.
The keyboard helper decodes scan-code set 2 prefixes and Pause; the mouse helper
decodes standard, wheel, and five-button packets for device IDs 0, 3, and 4.
No dynamic memory, hosted library, or operating-system service is required.

## Design References

- Intel University Program, *PS/2 Core* documentation.
- AMD, *XPS PS2 (v1.01a) Product Guide*.
- IBM Personal System/2 keyboard/mouse serial framing conventions.
