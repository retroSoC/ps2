// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

#include "ps2_keyboard.h"

#include <stddef.h>

#define PS2_KEYBOARD_DISABLE_SCANNING UINT8_C(0xF5)
#define PS2_KEYBOARD_ENABLE_SCANNING  UINT8_C(0xF4)
#define PS2_KEYBOARD_SET_SCAN_SET     UINT8_C(0xF0)
#define PS2_KEYBOARD_SET_LEDS         UINT8_C(0xED)
#define PS2_KEYBOARD_SET_TYPEMATIC    UINT8_C(0xF3)

void ps2_keyboard_decoder_init(ps2_keyboard_decoder_t *decoder) {
    if (decoder != NULL) {
        decoder->pause_index = 0U;
        decoder->extended = false;
        decoder->released = false;
    }
}

bool ps2_keyboard_decode_byte(ps2_keyboard_decoder_t *decoder, uint8_t byte,
                              ps2_key_event_t *event) {
    static const uint8_t pause_tail[7] = {UINT8_C(0x14), UINT8_C(0x77), UINT8_C(0xE1),
                                          UINT8_C(0xF0), UINT8_C(0x14), UINT8_C(0xF0),
                                          UINT8_C(0x77)};

    if ((decoder == NULL) || (event == NULL)) {
        return false;
    }
    if (decoder->pause_index != 0U) {
        const uint8_t expected = pause_tail[decoder->pause_index - 1U];

        if (byte != expected) {
            ps2_keyboard_decoder_init(decoder);
            return false;
        }
        decoder->pause_index++;
        if (decoder->pause_index == 8U) {
            event->scan_code = UINT16_C(0xE177);
            event->pressed = true;
            event->extended = true;
            ps2_keyboard_decoder_init(decoder);
            return true;
        }
        return false;
    }
    if (byte == UINT8_C(0xE1)) {
        decoder->pause_index = 1U;
        return false;
    }
    if (byte == UINT8_C(0xE0)) {
        decoder->extended = true;
        return false;
    }
    if (byte == UINT8_C(0xF0)) {
        decoder->released = true;
        return false;
    }

    event->scan_code = decoder->extended ? (UINT16_C(0xE000) | byte) : byte;
    event->pressed = !decoder->released;
    event->extended = decoder->extended;
    decoder->extended = false;
    decoder->released = false;
    return true;
}

ps2_status_t ps2_keyboard_init(uintptr_t base, ps2_device_info_t *info, uint32_t timeout) {
    const uint8_t scan_set = UINT8_C(2);
    ps2_device_info_t local_info;
    ps2_status_t status;

    if (info == NULL) {
        info = &local_info;
    }
    status = ps2_identify(base, info, timeout);
    if ((status != PS2_STATUS_OK) || (info->type != PS2_DEVICE_KEYBOARD)) {
        return (status == PS2_STATUS_OK) ? PS2_STATUS_UNSUPPORTED : status;
    }
    status = ps2_command(base, PS2_KEYBOARD_DISABLE_SCANNING, NULL, 0U, timeout);
    if (status == PS2_STATUS_OK) {
        status = ps2_command(base, PS2_KEYBOARD_SET_SCAN_SET, &scan_set, 1U, timeout);
    }
    if (status == PS2_STATUS_OK) {
        status = ps2_command(base, PS2_KEYBOARD_ENABLE_SCANNING, NULL, 0U, timeout);
    }
    return status;
}

ps2_status_t ps2_keyboard_set_leds(uintptr_t base, uint8_t led_mask, uint32_t timeout) {
    if ((led_mask & UINT8_C(0xF8)) != 0U) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    return ps2_command(base, PS2_KEYBOARD_SET_LEDS, &led_mask, 1U, timeout);
}

ps2_status_t ps2_keyboard_set_typematic(uintptr_t base, uint8_t value, uint32_t timeout) {
    return ps2_command(base, PS2_KEYBOARD_SET_TYPEMATIC, &value, 1U, timeout);
}
