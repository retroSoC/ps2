// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

#ifndef PS2_H
#define PS2_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    PS2_STATUS_OK = 0,
    PS2_STATUS_INVALID_ARGUMENT = -1,
    PS2_STATUS_TIMEOUT = -2,
    PS2_STATUS_IO_ERROR = -3,
    PS2_STATUS_PROTOCOL_ERROR = -4,
    PS2_STATUS_UNSUPPORTED = -5
} ps2_status_t;

typedef enum {
    PS2_DEVICE_UNKNOWN = 0,
    PS2_DEVICE_KEYBOARD = 1,
    PS2_DEVICE_MOUSE = 2
} ps2_device_type_t;

typedef struct {
    uint32_t source_clock_hz;
    uint32_t frame_timeout_us;
    uint8_t filter_cycles;
    uint8_t rx_watermark;
    uint8_t tx_watermark;
} ps2_config_t;

typedef struct {
    uint8_t data;
    uint8_t errors;
    uint8_t remaining;
} ps2_rx_byte_t;

typedef struct {
    ps2_device_type_t type;
    uint8_t id[2];
    uint8_t id_length;
} ps2_device_info_t;

typedef struct {
    uint32_t flags;
    uint32_t rx_level;
    uint32_t tx_level;
    uint32_t errors;
    uint32_t interrupt_state;
} ps2_controller_status_t;

ps2_status_t ps2_configure(uintptr_t base, const ps2_config_t *config, uint32_t timeout);
ps2_status_t ps2_init(uintptr_t base, uint32_t source_clock_hz);
ps2_status_t ps2_write(uintptr_t base, const uint8_t *data, size_t length, uint32_t timeout);
ps2_status_t ps2_read(uintptr_t base, ps2_rx_byte_t *data, size_t length, uint32_t timeout);
ps2_status_t ps2_command(uintptr_t base, uint8_t command, const uint8_t *parameters,
                         size_t parameter_count, uint32_t timeout);
ps2_status_t ps2_identify(uintptr_t base, ps2_device_info_t *info, uint32_t timeout);
ps2_status_t ps2_flush(uintptr_t base, bool flush_rx, bool flush_tx);
ps2_status_t ps2_abort(uintptr_t base);
ps2_status_t ps2_get_status(uintptr_t base, ps2_controller_status_t *status);
ps2_status_t ps2_irq_enable(uintptr_t base, uint32_t mask);
ps2_status_t ps2_irq_ack(uintptr_t base, uint32_t mask);
ps2_status_t ps2_irq_test(uintptr_t base, uint32_t mask);

#endif
