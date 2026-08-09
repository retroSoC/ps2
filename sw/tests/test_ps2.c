// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>

#include "ps2.h"
#include "ps2_keyboard.h"
#include "ps2_mouse.h"

static void test_keyboard_decoder(void) {
    ps2_keyboard_decoder_t decoder;
    ps2_key_event_t event;
    const uint8_t pause[] = {UINT8_C(0xE1), UINT8_C(0x14), UINT8_C(0x77), UINT8_C(0xE1),
                             UINT8_C(0xF0), UINT8_C(0x14), UINT8_C(0xF0), UINT8_C(0x77)};

    ps2_keyboard_decoder_init(&decoder);
    assert(ps2_keyboard_decode_byte(&decoder, UINT8_C(0x1C), &event));
    assert(event.pressed && !event.extended && (event.scan_code == UINT16_C(0x001C)));
    assert(!ps2_keyboard_decode_byte(&decoder, UINT8_C(0xF0), &event));
    assert(ps2_keyboard_decode_byte(&decoder, UINT8_C(0x1C), &event));
    assert(!event.pressed && (event.scan_code == UINT16_C(0x001C)));
    assert(!ps2_keyboard_decode_byte(&decoder, UINT8_C(0xE0), &event));
    assert(ps2_keyboard_decode_byte(&decoder, UINT8_C(0x75), &event));
    assert(event.extended && (event.scan_code == UINT16_C(0xE075)));
    for (uint32_t index = 0U; index < 7U; index++) {
        assert(!ps2_keyboard_decode_byte(&decoder, pause[index], &event));
    }
    assert(ps2_keyboard_decode_byte(&decoder, pause[7], &event));
    assert(event.pressed && event.extended && (event.scan_code == UINT16_C(0xE177)));
}

static void test_mouse_decoder(void) {
    ps2_mouse_decoder_t decoder;
    ps2_mouse_event_t event;

    ps2_mouse_decoder_init(&decoder, 0U);
    assert(!ps2_mouse_decode_byte(&decoder, UINT8_C(0x00), &event));
    assert(!ps2_mouse_decode_byte(&decoder, UINT8_C(0x19), &event));
    assert(!ps2_mouse_decode_byte(&decoder, UINT8_C(0xFE), &event));
    assert(ps2_mouse_decode_byte(&decoder, UINT8_C(0x03), &event));
    assert((event.dx == -2) && (event.dy == 3) && (event.buttons == 1U));

    ps2_mouse_decoder_init(&decoder, 4U);
    assert(!ps2_mouse_decode_byte(&decoder, UINT8_C(0x08), &event));
    assert(!ps2_mouse_decode_byte(&decoder, UINT8_C(0x02), &event));
    assert(!ps2_mouse_decode_byte(&decoder, UINT8_C(0x01), &event));
    assert(ps2_mouse_decode_byte(&decoder, UINT8_C(0x3F), &event));
    assert((event.dx == 2) && (event.dy == 1) && (event.wheel == -1));
    assert((event.buttons & UINT8_C(0x18)) == UINT8_C(0x18));
}

int main(void) {
    test_keyboard_decoder();
    test_mouse_decoder();
    assert(ps2_init((uintptr_t)0U, UINT32_C(72000000)) == PS2_STATUS_INVALID_ARGUMENT);
    assert(ps2_keyboard_set_leds((uintptr_t)1U, UINT8_C(0x08), 1U) == PS2_STATUS_INVALID_ARGUMENT);
    assert(ps2_mouse_set_resolution((uintptr_t)1U, 4U, 1U) == PS2_STATUS_INVALID_ARGUMENT);
    return 0;
}
