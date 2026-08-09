// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

#include "ps2.h"

#include <stdbool.h>

#include "ps2_regs.h"

#define PS2_ACK_BYTE      UINT8_C(0xFA)
#define PS2_RESEND_BYTE   UINT8_C(0xFE)
#define PS2_RESET_BYTE    UINT8_C(0xFF)
#define PS2_IDENTIFY_BYTE UINT8_C(0xF2)
#define PS2_BAT_OK_BYTE   UINT8_C(0xAA)
#define PS2_MAX_RESENDS   3U
#define PS2_MAX_TIMING    UINT32_C(0x00FFFFFF)

static volatile uint32_t *ps2_register(uintptr_t base, uint32_t offset) {
    return (volatile uint32_t *)(base + (uintptr_t)offset);
}

static uint32_t ps2_read_register(uintptr_t base, uint32_t offset) {
    return *ps2_register(base, offset);
}

static void ps2_write_register(uintptr_t base, uint32_t offset, uint32_t value) {
    *ps2_register(base, offset) = value;
}

static ps2_status_t ps2_timeout_cycles(uint32_t source_clock_hz, uint32_t timeout_us,
                                       uint32_t *cycles) {
    uint64_t value;

    if ((source_clock_hz == 0U) || (timeout_us == 0U) || (cycles == NULL)) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    value =
        (((uint64_t)source_clock_hz * (uint64_t)timeout_us) + UINT64_C(999999)) / UINT64_C(1000000);
    if ((value == 0U) || (value > PS2_MAX_TIMING)) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    *cycles = (uint32_t)value;
    return PS2_STATUS_OK;
}

ps2_status_t ps2_configure(uintptr_t base, const ps2_config_t *config, uint32_t timeout) {
    uint32_t inhibit_cycles;
    uint32_t frame_timeout_cycles;
    ps2_status_t status;

    if ((base == (uintptr_t)0U) || (config == NULL) || (config->filter_cycles == 0U) ||
        (config->filter_cycles > 15U) || (config->rx_watermark == 0U)) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    status = ps2_timeout_cycles(config->source_clock_hz, UINT32_C(120), &inhibit_cycles);
    if (status == PS2_STATUS_OK) {
        status = ps2_timeout_cycles(config->source_clock_hz, config->frame_timeout_us,
                                    &frame_timeout_cycles);
    }
    if (status != PS2_STATUS_OK) {
        return status;
    }

    ps2_write_register(base, PS2_CTRL_OFFSET, 0U);
    while (((ps2_read_register(base, PS2_STATUS_OFFSET) &
             (PS2_STATUS_RX_ACTIVE_MASK | PS2_STATUS_TX_ACTIVE_MASK)) != 0U) &&
           (timeout != 0U)) {
        timeout--;
    }
    if ((ps2_read_register(base, PS2_STATUS_OFFSET) &
         (PS2_STATUS_RX_ACTIVE_MASK | PS2_STATUS_TX_ACTIVE_MASK)) != 0U) {
        return PS2_STATUS_TIMEOUT;
    }

    ps2_write_register(base, PS2_FIFO_CTRL_OFFSET,
                       PS2_FIFO_CTRL_RX_FLUSH_MASK | PS2_FIFO_CTRL_TX_FLUSH_MASK);
    ps2_write_register(base, PS2_ERROR_STATUS_OFFSET, PS2_ERROR_VALID_MASK);
    ps2_write_register(base, PS2_INTR_STATE_OFFSET, PS2_INTR_VALID_MASK);
    ps2_write_register(base, PS2_RX_WATERMARK_OFFSET, config->rx_watermark);
    ps2_write_register(base, PS2_TX_WATERMARK_OFFSET, config->tx_watermark);
    ps2_write_register(base, PS2_FILTER_OFFSET, config->filter_cycles);
    ps2_write_register(base, PS2_INHIBIT_CYCLES_OFFSET, inhibit_cycles);
    ps2_write_register(base, PS2_FRAME_TIMEOUT_OFFSET, frame_timeout_cycles);
    ps2_write_register(base, PS2_CTRL_OFFSET, PS2_CTRL_ENABLE_MASK);

    return ((ps2_read_register(base, PS2_STATUS_OFFSET) & PS2_STATUS_CONFIG_VALID_MASK) != 0U)
               ? PS2_STATUS_OK
               : PS2_STATUS_IO_ERROR;
}

ps2_status_t ps2_init(uintptr_t base, uint32_t source_clock_hz) {
    const ps2_config_t config = {
        .source_clock_hz = source_clock_hz,
        .frame_timeout_us = UINT32_C(2000),
        .filter_cycles = UINT8_C(3),
        .rx_watermark = UINT8_C(1),
        .tx_watermark = UINT8_C(0),
    };

    return ps2_configure(base, &config, UINT32_C(1000000));
}

ps2_status_t ps2_write(uintptr_t base, const uint8_t *data, size_t length, uint32_t timeout) {
    size_t index;

    if ((base == (uintptr_t)0U) || ((data == NULL) && (length != 0U))) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    for (index = 0U; index < length; index++) {
        while ((ps2_read_register(base, PS2_STATUS_OFFSET) & PS2_STATUS_TX_FULL_MASK) != 0U) {
            if (timeout == 0U) {
                return PS2_STATUS_TIMEOUT;
            }
            timeout--;
        }
        ps2_write_register(base, PS2_TXDATA_OFFSET, data[index]);
    }
    return PS2_STATUS_OK;
}

ps2_status_t ps2_read(uintptr_t base, ps2_rx_byte_t *data, size_t length, uint32_t timeout) {
    size_t index;

    if ((base == (uintptr_t)0U) || ((data == NULL) && (length != 0U))) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    for (index = 0U; index < length; index++) {
        uint32_t value;

        do {
            value = ps2_read_register(base, PS2_RXDATA_OFFSET);
            if ((value & PS2_RXDATA_VALID_MASK) == 0U) {
                if (timeout == 0U) {
                    return PS2_STATUS_TIMEOUT;
                }
                timeout--;
            }
        } while ((value & PS2_RXDATA_VALID_MASK) == 0U);

        data[index].data = (uint8_t)(value & PS2_RXDATA_DATA_MASK);
        data[index].errors = (uint8_t)((value & PS2_RXDATA_ERROR_MASK) >> PS2_RXDATA_ERROR_SHIFT);
        data[index].remaining =
            (uint8_t)((value & PS2_RXDATA_LEVEL_MASK) >> PS2_RXDATA_LEVEL_SHIFT);
        if (data[index].errors != 0U) {
            return PS2_STATUS_IO_ERROR;
        }
    }
    return PS2_STATUS_OK;
}

static ps2_status_t ps2_write_with_ack(uintptr_t base, uint8_t value, uint32_t timeout) {
    uint32_t attempt;

    for (attempt = 0U; attempt < PS2_MAX_RESENDS; attempt++) {
        ps2_rx_byte_t response;
        ps2_status_t status = ps2_write(base, &value, 1U, timeout);

        if (status != PS2_STATUS_OK) {
            return status;
        }
        status = ps2_read(base, &response, 1U, timeout);
        if (status != PS2_STATUS_OK) {
            return status;
        }
        if (response.data == PS2_ACK_BYTE) {
            return PS2_STATUS_OK;
        }
        if (response.data != PS2_RESEND_BYTE) {
            return PS2_STATUS_PROTOCOL_ERROR;
        }
    }
    return PS2_STATUS_IO_ERROR;
}

ps2_status_t ps2_command(uintptr_t base, uint8_t command, const uint8_t *parameters,
                         size_t parameter_count, uint32_t timeout) {
    size_t index;
    ps2_status_t status;

    if ((base == (uintptr_t)0U) || ((parameters == NULL) && (parameter_count != 0U))) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    status = ps2_write_with_ack(base, command, timeout);
    for (index = 0U; (index < parameter_count) && (status == PS2_STATUS_OK); index++) {
        status = ps2_write_with_ack(base, parameters[index], timeout);
    }
    return status;
}

ps2_status_t ps2_identify(uintptr_t base, ps2_device_info_t *info, uint32_t timeout) {
    ps2_rx_byte_t response;
    ps2_status_t status;

    if ((base == (uintptr_t)0U) || (info == NULL)) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    info->type = PS2_DEVICE_UNKNOWN;
    info->id[0] = 0U;
    info->id[1] = 0U;
    info->id_length = 0U;

    status = ps2_flush(base, true, true);
    if (status == PS2_STATUS_OK) {
        status = ps2_write_with_ack(base, PS2_RESET_BYTE, timeout);
    }
    if (status == PS2_STATUS_OK) {
        status = ps2_read(base, &response, 1U, timeout);
    }
    if ((status != PS2_STATUS_OK) || (response.data != PS2_BAT_OK_BYTE)) {
        return (status == PS2_STATUS_OK) ? PS2_STATUS_PROTOCOL_ERROR : status;
    }

    if ((ps2_read_register(base, PS2_STATUS_OFFSET) & PS2_STATUS_RX_EMPTY_MASK) == 0U) {
        status = ps2_read(base, &response, 1U, timeout);
        if (status != PS2_STATUS_OK) {
            return status;
        }
        if ((response.data == 0U) || (response.data == 3U) || (response.data == 4U)) {
            info->type = PS2_DEVICE_MOUSE;
            info->id[0] = response.data;
            info->id_length = 1U;
            return PS2_STATUS_OK;
        }
    }

    status = ps2_write_with_ack(base, PS2_IDENTIFY_BYTE, timeout);
    if (status == PS2_STATUS_OK) {
        status = ps2_read(base, &response, 1U, timeout);
    }
    if (status != PS2_STATUS_OK) {
        return status;
    }
    info->id[0] = response.data;
    info->id_length = 1U;
    if ((response.data == 0U) || (response.data == 3U) || (response.data == 4U)) {
        info->type = PS2_DEVICE_MOUSE;
    } else if ((response.data == UINT8_C(0xAB)) || (response.data == UINT8_C(0xAC))) {
        status = ps2_read(base, &response, 1U, timeout);
        if (status == PS2_STATUS_OK) {
            info->id[1] = response.data;
            info->id_length = 2U;
            info->type = PS2_DEVICE_KEYBOARD;
        }
    }
    return (info->type == PS2_DEVICE_UNKNOWN) ? PS2_STATUS_UNSUPPORTED : status;
}

ps2_status_t ps2_flush(uintptr_t base, bool flush_rx, bool flush_tx) {
    uint32_t command = 0U;

    if ((base == (uintptr_t)0U) || ((!flush_rx) && (!flush_tx))) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    if (flush_rx) {
        command |= PS2_FIFO_CTRL_RX_FLUSH_MASK;
    }
    if (flush_tx) {
        command |= PS2_FIFO_CTRL_TX_FLUSH_MASK;
    }
    ps2_write_register(base, PS2_FIFO_CTRL_OFFSET, command);
    return PS2_STATUS_OK;
}

ps2_status_t ps2_abort(uintptr_t base) {
    if (base == (uintptr_t)0U) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    ps2_write_register(base, PS2_COMMAND_OFFSET, PS2_COMMAND_ABORT_MASK);
    return PS2_STATUS_OK;
}

ps2_status_t ps2_get_status(uintptr_t base, ps2_controller_status_t *status) {
    uint32_t levels;

    if ((base == (uintptr_t)0U) || (status == NULL)) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    levels = ps2_read_register(base, PS2_FIFO_STATUS_OFFSET);
    status->flags = ps2_read_register(base, PS2_STATUS_OFFSET);
    status->rx_level = levels & UINT32_C(0xFF);
    status->tx_level = (levels >> 8U) & UINT32_C(0xFF);
    status->errors = ps2_read_register(base, PS2_ERROR_STATUS_OFFSET);
    status->interrupt_state = ps2_read_register(base, PS2_INTR_STATE_OFFSET);
    return PS2_STATUS_OK;
}

ps2_status_t ps2_irq_enable(uintptr_t base, uint32_t mask) {
    if ((base == (uintptr_t)0U) || ((mask & ~PS2_INTR_VALID_MASK) != 0U)) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    ps2_write_register(base, PS2_INTR_ENABLE_OFFSET, mask);
    return PS2_STATUS_OK;
}

ps2_status_t ps2_irq_ack(uintptr_t base, uint32_t mask) {
    if ((base == (uintptr_t)0U) || (mask == 0U) || ((mask & ~PS2_INTR_VALID_MASK) != 0U)) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    ps2_write_register(base, PS2_INTR_STATE_OFFSET, mask);
    return PS2_STATUS_OK;
}

ps2_status_t ps2_irq_test(uintptr_t base, uint32_t mask) {
    if ((base == (uintptr_t)0U) || (mask == 0U) || ((mask & ~PS2_INTR_VALID_MASK) != 0U)) {
        return PS2_STATUS_INVALID_ARGUMENT;
    }
    ps2_write_register(base, PS2_INTR_TEST_OFFSET, mask);
    return PS2_STATUS_OK;
}
