/*
 * Minimal T234 development harness for NVIDIA OP-TEE bring-up.
 * This is not a complete Jetson or Tegra234 SoC model.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "qemu/osdep.h"
#include "qapi/error.h"
#include "qemu/error-report.h"
#include "qemu/log.h"
#include "qemu/module.h"
#include "qemu/units.h"
#include "chardev/char-fe.h"
#include "hw/core/boards.h"
#include "hw/core/loader.h"
#include "hw/arm/machines-qom.h"
#include "system/address-spaces.h"
#include "system/system.h"
#include "system/tcg.h"
#include "target/arm/cpu.h"

#define TYPE_JETSON_T234_DEV MACHINE_TYPE_NAME("jetson-t234-dev")
OBJECT_DECLARE_SIMPLE_TYPE(JetsonT234DevState, JETSON_T234_DEV)

#define TCU_BASE       0x0c198000
#define TCU_SIZE       0x1000
#define SECURE_BASE    0x80000000
#define SECURE_SIZE    (64 * MiB)
#define OPTEE_MAX_SIZE 0x03fc0000
#define DT_BASE        0x83ff0000
#define DT_MAX_SIZE    0x10000
#define NS_BASE        0x90000000
#define BOOT_SIZE      0x10000
#define TCU_TRIGGER    (1U << 31)
#define TCU_FLUSH      (1U << 26)

struct JetsonT234DevState {
    MachineState parent_obj;
    MemoryRegion secure_memory;
    MemoryRegion secure_ram;
    MemoryRegion boot_rom;
    MemoryRegion tcu;
    AddressSpace secure_as;
    CharFrontend console;
};

static uint64_t tcu_read(void *opaque, hwaddr offset, unsigned size)
{
    if (offset) {
        qemu_log_mask(LOG_GUEST_ERROR,
                      "jetson-tcu: unsupported read offset 0x%"
                      HWADDR_PRIx "\n",
                      offset);
    }
    /* Transmit is synchronously consumed; the mailbox is never busy. */
    return 0;
}

static void tcu_write(void *opaque, hwaddr offset, uint64_t value,
                      unsigned size)
{
    JetsonT234DevState *s = opaque;
    uint8_t bytes[3];
    unsigned count = (value >> 24) & 3;

    if (offset || !(value & TCU_TRIGGER)) {
        qemu_log_mask(LOG_GUEST_ERROR,
                      "jetson-tcu: unsupported write offset 0x%" HWADDR_PRIx
                      " value 0x%08" PRIx64 "\n", offset, value);
        return;
    }
    if (count) {
        for (unsigned i = 0; i < count; i++) {
            bytes[i] = value >> (8 * i);
        }
        if (qemu_chr_fe_backend_connected(&s->console)) {
            qemu_chr_fe_write_all(&s->console, bytes, count);
        }
    } else if (!(value & TCU_FLUSH)) {
        qemu_log_mask(LOG_GUEST_ERROR, "jetson-tcu: empty non-flush packet\n");
    }
}

static const MemoryRegionOps tcu_ops = {
    .read = tcu_read,
    .write = tcu_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = { .min_access_size = 4, .max_access_size = 4,
               .unaligned = false },
    .impl = { .min_access_size = 4, .max_access_size = 4 },
};

static void load_secure_image(JetsonT234DevState *s, const char *filename,
                              hwaddr address, uint64_t limit)
{
    if (filename && load_image_targphys_as(filename, address, limit,
                                           &s->secure_as, &error_fatal) < 0) {
        error_report("jetson-t234-dev: cannot load %s", filename);
        exit(EXIT_FAILURE);
    }
}

static void jetson_t234_dev_init(MachineState *machine)
{
    JetsonT234DevState *s = JETSON_T234_DEV(machine);
    MemoryRegion *sysmem = get_system_memory();
    Object *cpu;

    if (!tcg_enabled()) {
        error_report("jetson-t234-dev supports TCG only");
        exit(EXIT_FAILURE);
    }
    if (machine->ram_size != 128 * MiB) {
        error_report("jetson-t234-dev requires 128 MiB non-secure RAM");
        exit(EXIT_FAILURE);
    }
    memory_region_add_subregion(sysmem, NS_BASE, machine->ram);
    memory_region_init(&s->secure_memory, OBJECT(machine),
                       "jetson-t234-dev.secure-memory", UINT64_MAX);
    memory_region_add_subregion_overlap(&s->secure_memory, 0, sysmem, -1);
    memory_region_init_ram(&s->secure_ram, NULL,
                           "jetson-t234-dev.secure-ram", SECURE_SIZE,
                           &error_fatal);
    memory_region_add_subregion(&s->secure_memory, SECURE_BASE, &s->secure_ram);
    memory_region_init_rom(&s->boot_rom, NULL,
                           "jetson-t234-dev.boot-rom", BOOT_SIZE, &error_fatal);
    memory_region_add_subregion(&s->secure_memory, 0, &s->boot_rom);
    address_space_init(&s->secure_as, &s->secure_memory,
                       "jetson-t234-dev.secure-loader");

    qemu_chr_fe_init(&s->console, serial_hd(0), &error_fatal);
    memory_region_init_io(&s->tcu, OBJECT(machine), &tcu_ops, s,
                          "jetson-t234-dev.tcu", TCU_SIZE);
    /* Console access is shared; only secure RAM and boot ROM are private. */
    memory_region_add_subregion(sysmem, TCU_BASE, &s->tcu);

    cpu = object_new(machine->cpu_type);
    object_property_set_bool(cpu, "has_el3", true, &error_fatal);
    object_property_set_link(cpu, "memory", OBJECT(sysmem), &error_fatal);
    object_property_set_link(cpu, "secure-memory", OBJECT(&s->secure_memory),
                             &error_fatal);
    qdev_realize(DEVICE(cpu), NULL, &error_fatal);
    object_unref(cpu);

    load_secure_image(s, machine->firmware, 0, BOOT_SIZE);
    load_secure_image(s, machine->kernel_filename, SECURE_BASE, OPTEE_MAX_SIZE);
    load_secure_image(s, machine->dtb, DT_BASE, DT_MAX_SIZE);
}

static void jetson_t234_dev_class_init(ObjectClass *oc, const void *data)
{
    MachineClass *mc = MACHINE_CLASS(oc);
    static const char *const cpu_types[] = { ARM_CPU_TYPE_NAME("max"), NULL };

    mc->desc = "T234 OP-TEE development harness (incomplete, TCG only)";
    mc->init = jetson_t234_dev_init;
    mc->default_cpu_type = ARM_CPU_TYPE_NAME("max");
    mc->valid_cpu_types = cpu_types;
    mc->max_cpus = 1;
    mc->default_ram_size = 128 * MiB;
    mc->default_ram_id = "jetson-t234-dev.nonsecure-ram";
    mc->ignore_memory_transaction_failures = false;
}

static const TypeInfo jetson_t234_dev_type = {
    .name = TYPE_JETSON_T234_DEV,
    .parent = TYPE_MACHINE,
    .instance_size = sizeof(JetsonT234DevState),
    .class_init = jetson_t234_dev_class_init,
    .interfaces = aarch64_machine_interfaces,
};

static void jetson_t234_dev_register_types(void)
{
    type_register_static(&jetson_t234_dev_type);
}

type_init(jetson_t234_dev_register_types)
