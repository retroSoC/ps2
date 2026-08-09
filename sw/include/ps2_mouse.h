// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

#ifndef PS2_MOUSE_H
#define PS2_MOUSE_H

#include <stdbool.h>
#include <stdint.h>

#include "ps2.h"

typedef enum { PS2_MOUSE_MODE_STREAM = 0, PS2_MOUSE_MODE_REMOTE = 1 } ps2_mouse_mode_t;

typedef struct {
    int16_t dx;
    int16_t dy;
    int8_t wheel;
    uint8_t buttons;
    bool x_overflow;
    bool y_overflow;
} ps2_mouse_event_t;

typedef struct {
    uint8_t bytes[4];
    uint8_t index;
    uint8_t device_id;
} ps2_mouse_decoder_t;

void ps2_mouse_decoder_init(ps2_mouse_decoder_t *decoder, uint8_t device_id);
bool ps2_mouse_decode_byte(ps2_mouse_decoder_t *decoder, uint8_t byte, ps2_mouse_event_t *event);
ps2_status_t ps2_mouse_init(uintptr_t base, ps2_device_info_t *info, uint32_t timeout);
ps2_status_t ps2_mouse_set_mode(uintptr_t base, ps2_mouse_mode_t mode, uint32_t timeout);
ps2_status_t ps2_mouse_set_sample_rate(uintptr_t base, uint8_t rate, uint32_t timeout);
ps2_status_t ps2_mouse_set_resolution(uintptr_t base, uint8_t resolution, uint32_t timeout);
ps2_status_t ps2_mouse_enable_reporting(uintptr_t base, bool enable, uint32_t timeout);

#endif
