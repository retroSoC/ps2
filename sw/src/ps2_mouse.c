// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

#include "ps2_mouse.h"

#include <stddef.h>

#define PS2_MOUSE_SET_DEFAULTS    UINT8_C(0xF6)
#define PS2_MOUSE_SET_STREAM      UINT8_C(0xEA)
#define PS2_MOUSE_SET_REMOTE      UINT8_C(0xF0)
#define PS2_MOUSE_SET_SAMPLE_RATE UINT8_C(0xF3)
#define PS2_MOUSE_SET_RESOLUTION  UINT8_C(0xE8)
#define PS2_MOUSE_ENABLE_REPORT   UINT8_C(0xF4)
#define PS2_MOUSE_DISABLE_REPORT  UINT8_C(0xF5)

static int16_t ps2_mouse_delta(uint8_t value, bool negative) {
    return negative ? (int16_t)((uint16_t)value | UINT16_C(0xFF00)) : (int16_t)value;
}

void ps2_mouse_decoder_init(ps2_mouse_decoder_t *decoder, uint8_t device_id) {
    if (decoder != NULL) {
        decoder->index = 0U;
        decoder->device_id = device_id;
    }
}

bool ps2_mouse_decode_byte(ps2_mouse_decoder_t *decoder, uint8_t byte, ps2_mouse_event_t *event) {
    uint8_t packet_length;

    if ((decoder == NULL) || (event == NULL)) {
        return false;
    }
    packet_length = ((decoder->device_id == 3U) || (decoder->device_id == 4U)) ? 4U : 3U;
    if ((decoder->index == 0U) && ((byte & UINT8_C(0x08)) == 0U)) {
        return false;
    }
    decoder->bytes[decoder->index] = byte;
    decoder->index++;
    if (decoder->index < packet_length) {
        return false;
    }

    event->buttons = decoder->bytes[0] & UINT8_C(0x07);
    event->dx = ps2_mouse_delta(decoder->bytes[1], (decoder->bytes[0] & UINT8_C(0x10)) != 0U);
    event->dy = ps2_mouse_delta(decoder->bytes[2], (decoder->bytes[0] & UINT8_C(0x20)) != 0U);
    event->x_overflow = (decoder->bytes[0] & UINT8_C(0x40)) != 0U;
    event->y_overflow = (decoder->bytes[0] & UINT8_C(0x80)) != 0U;
    event->wheel = 0;
    if (packet_length == 4U) {
        const uint8_t wheel = decoder->bytes[3] & UINT8_C(0x0F);

        event->wheel =
            ((wheel & UINT8_C(0x08)) != 0U) ? (int8_t)(wheel | UINT8_C(0xF0)) : (int8_t)wheel;
        if (decoder->device_id == 4U) {
            event->buttons |= (uint8_t)((decoder->bytes[3] & UINT8_C(0x30)) >> 1U);
        }
    }
    decoder->index = 0U;
    return true;
}

ps2_status_t ps2_mouse_init(uintptr_t base, ps2_device_info_t *info, uint32_t timeout) {
    ps2_device_info_t local_info;
    ps2_status_t status;

    if (info == NULL) {
        info = &local_info;
    }
    status = ps2_identify(base, info, timeout);
    if ((status != PS2_STATUS_OK) || (info->type != PS2_DEVICE_MOUSE)) {
        return (status == PS2_STATUS_OK) ? PS2_STATUS_UNSUPPORTED : status;
    }
    status = ps2_command(base, PS2_MOUSE_SET_DEFAULTS, NULL, 0U, timeout);
    if (status == PS2_STATUS_OK) {
        status = ps2_command(base, PS2_MOUSE_SET_STREAM, NULL, 0U, timeout);
    }
    if (status == PS2_STATUS_OK) {
        status = ps2_command(base, PS2_MOUSE_ENABLE_REPORT, NULL, 0U, timeout);
    }
    return status;
}

ps2_status_t ps2_mouse_set_mode(uintptr_t base, ps2_mouse_mode_t mode, uint32_t timeout) {
    if ((mode != PS2_MOUSE_MODE_STREAM) && (mode != PS2_MOUSE_MODE_REMOTE)) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    return ps2_command(
        base, (mode == PS2_MOUSE_MODE_STREAM) ? PS2_MOUSE_SET_STREAM : PS2_MOUSE_SET_REMOTE, NULL,
        0U, timeout);
}

ps2_status_t ps2_mouse_set_sample_rate(uintptr_t base, uint8_t rate, uint32_t timeout) {
    return ps2_command(base, PS2_MOUSE_SET_SAMPLE_RATE, &rate, 1U, timeout);
}

ps2_status_t ps2_mouse_set_resolution(uintptr_t base, uint8_t resolution, uint32_t timeout) {
    if (resolution > 3U) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    return ps2_command(base, PS2_MOUSE_SET_RESOLUTION, &resolution, 1U, timeout);
}

ps2_status_t ps2_mouse_enable_reporting(uintptr_t base, bool enable, uint32_t timeout) {
    return ps2_command(base, enable ? PS2_MOUSE_ENABLE_REPORT : PS2_MOUSE_DISABLE_REPORT, NULL, 0U,
                       timeout);
}
