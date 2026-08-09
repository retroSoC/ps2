# Integration Guide

Instantiate `apb4_ps2` using complete named connections. Set `PCLK_HZ` to the
actual APB clock and retain the default 16-entry FIFOs unless traffic analysis
justifies another power-of-two depth.

Connect `ps2_clk_o` and `ps2_dat_o` to zero-valued pad data inputs and connect
the corresponding output-enables as active-high drive-low controls. Each pad
must be open drain with a board or pad pull-up. Feed the resolved pad values
back to `ps2_clk_i` and `ps2_dat_i`; the host must observe device stretching
and arbitration on those resolved inputs.

The APB clock and active-low reset are supplied by the Common `apb4_if`. The
physical inputs may be asynchronous because the IP includes two-stage
synchronizers. Static timing constraints should mark pad-to-first-synchronizer
paths asynchronous and preserve the synchronizer flops; do not false-path the
filtered signal after the synchronizer.

Route `irq_o` into a level-sensitive interrupt input. Firmware must clear the
corresponding `INTR_STATE` RW1C bit after draining data or handling the error.
Watermark causes are sticky events, so clearing while the condition remains
true may set them again on the next cycle.

The IP supports one physical device at a time. A connector shared with GPIO or
another function must switch input, output-data, and output-enable paths as one
atomic mux selection. The integration must release both lines before changing
ownership. Do not connect a keyboard and mouse electrically in parallel.

Software should validate `IP_ID`, `IP_VERSION`, and the ABI field in
`CAPABILITY` before programming optional fields. The checked-in C register
header is manually maintained; `make register-check` is the required parity
gate until a project-wide register generator is introduced.
