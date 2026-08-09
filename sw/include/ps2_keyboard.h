// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

#ifndef PS2_KEYBOARD_H
#define PS2_KEYBOARD_H

#include <stdbool.h>
#include <stdint.h>

#include "ps2.h"

typedef struct {
    uint16_t scan_code;
    bool pressed;
    bool extended;
} ps2_key_event_t;

typedef struct {
    uint8_t pause_bytes[7];
    uint8_t pause_index;
    bool extended;
    bool released;
} ps2_keyboard_decoder_t;

void ps2_keyboard_decoder_init(ps2_keyboard_decoder_t *decoder);
bool ps2_keyboard_decode_byte(ps2_keyboard_decoder_t *decoder, uint8_t byte,
                              ps2_key_event_t *event);
ps2_status_t ps2_keyboard_init(uintptr_t base, ps2_device_info_t *info, uint32_t timeout);
ps2_status_t ps2_keyboard_set_leds(uintptr_t base, uint8_t led_mask, uint32_t timeout);
ps2_status_t ps2_keyboard_set_typematic(uintptr_t base, uint8_t value, uint32_t timeout);

#endif
