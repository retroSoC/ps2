# Release Checklist

- [ ] ABI V2 register offsets and fields are reviewed.
- [ ] Keyboard and mouse software APIs are reviewed without legacy assumptions.
- [ ] All output-enable connections reach open-drain-capable pads.
- [ ] `make register-check` confirms RTL/C parity.
- [ ] Format, lint, Icarus, Verilator, host, synthesis, and formal gates pass.
- [ ] Common and tool revisions match `config/dependencies.lock.json`.
- [ ] SoC interrupt routing, address decode, reset, CDC, and timing are signed off.
- [ ] Changelog and implementation version are updated.
