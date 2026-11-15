/*
 * Minimal T234 development harness for NVIDIA OP-TEE bring-up.
 * This is not a complete Jetson or Tegra234 SoC model.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "qemu/osdep.h"
#include "qapi/error.h"
#include "qemu/error-report.h"
#include "qemu/bswap.h"
#include "qemu/log.h"
#include "qemu/module.h"
#include "qemu/units.h"
#include "chardev/char-fe.h"
#include "hw/core/boards.h"
#include "hw/core/loader.h"
#include "hw/arm/machines-qom.h"
#include "system/address-spaces.h"
#include "system/system.h"
#include "system/reset.h"
#include "system/tcg.h"
#include "target/arm/cpu.h"
#include "trace.h"

#define TYPE_JETSON_T234_DEV MACHINE_TYPE_NAME("jetson-t234-dev")
OBJECT_DECLARE_SIMPLE_TYPE(JetsonT234DevState, JETSON_T234_DEV)

#define FUSE_BASE      0x03810000
#define FUSE_SIZE      0x600

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
    MemoryRegion fuse;
    uint32_t fuse_words[FUSE_SIZE / 4];
    char *fuse_image;
    bool initialized;
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

/* Only the public identity/configuration registers used by this driver. */
static bool fuse_supported(hwaddr offset)
{
    switch (offset) {
    case 0x1a0: /* security mode */
    case 0x200: /* vendor */
    case 0x204: /* fab */
    case 0x208: /* lot 0 */
    case 0x20c: /* lot 1 */
    case 0x210: /* wafer */
    case 0x214: /* X coordinate */
    case 0x218: /* Y coordinate */
    case 0x220: /* reserved ECID field */
    case 0x268: /* boot security info */
    case 0x29c: /* ODM info */
    case 0x408: /* ODM ID 0 */
    case 0x40c: /* ODM ID 1 */
        return true;
    default:
        return false;
    }
}

static MemTxResult fuse_read(void *opaque, hwaddr offset, uint64_t *value,
                              unsigned size, MemTxAttrs attrs)
{
    JetsonT234DevState *s = opaque;

    if (!fuse_supported(offset)) {
        qemu_log_mask(LOG_GUEST_ERROR,
                      "jetson-fuse: unsupported read offset 0x%"
                      HWADDR_PRIx "\n", offset);
        return MEMTX_DECODE_ERROR;
    }
    *value = s->fuse_words[offset / 4];
    trace_jetson_t234_fuse_read(offset, *value);
    return MEMTX_OK;
}

static MemTxResult fuse_write(void *opaque, hwaddr offset, uint64_t value,
                               unsigned size, MemTxAttrs attrs)
{
    trace_jetson_t234_fuse_write_rejected(offset, value);
    qemu_log_mask(LOG_GUEST_ERROR,
                  "jetson-fuse: read-only write rejected at offset 0x%"
                  HWADDR_PRIx "\n", offset);
    return MEMTX_ACCESS_ERROR;
}

static const MemoryRegionOps fuse_ops = {
    .read_with_attrs = fuse_read,
    .write_with_attrs = fuse_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = { .min_access_size = 4, .max_access_size = 4,
               .unaligned = false },
    .impl = { .min_access_size = 4, .max_access_size = 4 },
};

static void create_fuse(JetsonT234DevState *s)
{
    g_autofree char *contents = NULL;
    g_autoptr(GError) error = NULL;
    gsize length;

    if (!s->fuse_image) {
        return; /* Keep the Stage A configuration available. */
    }
    if (!g_file_get_contents(s->fuse_image, &contents, &length, &error)) {
        error_report("jetson-fuse: %s", error->message);
        exit(EXIT_FAILURE);
    }
    if (length != FUSE_SIZE) {
        error_report("jetson-fuse: image must be exactly 0x600 bytes");
        exit(EXIT_FAILURE);
    }
    for (unsigned i = 0; i < FUSE_SIZE / 4; i++) {
        uint32_t value = ldl_le_p(contents + 4 * i);

        if (!fuse_supported(4 * i) && value) {
            error_report("jetson-fuse: nonzero unsupported offset 0x%x", 4 * i);
            exit(EXIT_FAILURE);
        }
        s->fuse_words[i] = value;
    }
    memory_region_init_io(&s->fuse, OBJECT(s), &fuse_ops, s,
                          "jetson-t234-dev.fuse", FUSE_SIZE);
    memory_region_add_subregion(&s->secure_memory, FUSE_BASE, &s->fuse);
}

static char *get_fuse_image(Object *obj, Error **errp)
{
    JetsonT234DevState *s = JETSON_T234_DEV(obj);

    return g_strdup(s->fuse_image ?: "");
}

static void set_fuse_image(Object *obj, const char *value, Error **errp)
{
    JetsonT234DevState *s = JETSON_T234_DEV(obj);

    if (s->initialized) {
        error_setg(errp,
                   "fuse-image is immutable after machine initialization");
        return;
    }
    if (!value || !*value) {
        error_setg(errp, "fuse-image requires a nonempty filename");
        return;
    }
    g_free(s->fuse_image);
    s->fuse_image = g_strdup(value);
}

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

    create_fuse(s);

    cpu = object_new(machine->cpu_type);
    object_property_set_bool(cpu, "has_el3", true, &error_fatal);
    object_property_set_link(cpu, "memory", OBJECT(sysmem), &error_fatal);
    object_property_set_link(cpu, "secure-memory", OBJECT(&s->secure_memory),
                             &error_fatal);
    qdev_realize(DEVICE(cpu), NULL, &error_fatal);
    qemu_register_resettable(cpu);
    object_unref(cpu);

    load_secure_image(s, machine->firmware, 0, BOOT_SIZE);
    load_secure_image(s, machine->kernel_filename, SECURE_BASE, OPTEE_MAX_SIZE);
    load_secure_image(s, machine->dtb, DT_BASE, DT_MAX_SIZE);
    s->initialized = true;
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
    object_class_property_add_str(oc, "fuse-image", get_fuse_image,
                                   set_fuse_image);
    object_class_property_set_description(oc, "fuse-image",
        "Read-only test Fuse register image (0x600 bytes, secure-only)");
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
