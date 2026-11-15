/* Functional fTPM profile using virt devices, not Tegra234 SE emulation.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "qemu/osdep.h"
#include "qapi/error.h"
#include "qemu/error-report.h"
#include "qemu/module.h"
#include "hw/arm/virt.h"
#include "hw/arm/machines-qom.h"

#define TYPE_JETSON_FTPM_VIRT MACHINE_TYPE_NAME("jetson-ftpm-virt")
OBJECT_DECLARE_SIMPLE_TYPE(JetsonFtpmVirtState, JETSON_FTPM_VIRT)

struct JetsonFtpmVirtState {
    VirtMachineState parent_obj;
    MemoryRegion identity;
    char *identity_file;
    bool initialized;
};
static void (*parent_init)(MachineState *);

static char *get_identity(Object *obj, Error **errp)
{
    return g_strdup(JETSON_FTPM_VIRT(obj)->identity_file ?: "");
}

static void set_identity(Object *obj, const char *value, Error **errp)
{
    JetsonFtpmVirtState *s = JETSON_FTPM_VIRT(obj);

    if (s->initialized) {
        error_setg(errp, "identity-file is immutable after initialization");
        return;
    }
    g_free(s->identity_file);
    s->identity_file = g_strdup(value);
}

static void ftpm_virt_init(MachineState *ms)
{
    JetsonFtpmVirtState *s = JETSON_FTPM_VIRT(ms);
    VirtMachineState *vms = VIRT_MACHINE(ms);
    g_autofree char *data = NULL;
    g_autoptr(GError) error = NULL;
    gsize size;

    parent_init(ms);
    if (!vms->secure || !s->identity_file) {
        error_report("jetson-ftpm-virt requires secure=on and identity-file");
        exit(EXIT_FAILURE);
    }
    if (!g_file_get_contents(s->identity_file, &data, &size, &error)) {
        error_report("identity-file: %s", error->message);
        exit(EXIT_FAILURE);
    }
    if (size != 72 || memcmp(data, "JFTPM001", 8)) {
        error_report("identity-file must be a 72-byte JFTPM001 image");
        exit(EXIT_FAILURE);
    }
    memory_region_init_rom(&s->identity, NULL, "ftpm-test-identity", 4096,
                           &error_fatal);
    memcpy(memory_region_get_ram_ptr(&s->identity), data, size);
    memory_region_add_subregion(vms->secure_sysmem, 0x0c200000, &s->identity);
    s->initialized = true;
}

static void ftpm_virt_class_init(ObjectClass *oc, const void *data)
{
    MachineClass *mc = MACHINE_CLASS(oc);

    parent_init = mc->init;
    mc->init = ftpm_virt_init;
    mc->desc = "NVIDIA fTPM functional profile with per-device test identity";
    object_class_property_add_str(oc, "identity-file", get_identity,
                                   set_identity);
}

static const TypeInfo ftpm_virt_type = {
    .name = TYPE_JETSON_FTPM_VIRT,
    .parent = TYPE_VIRT_MACHINE,
    .instance_size = sizeof(JetsonFtpmVirtState),
    .class_init = ftpm_virt_class_init,
    .interfaces = aarch64_machine_interfaces,
};

static void ftpm_virt_register_types(void)
{
    type_register_static(&ftpm_virt_type);
}
type_init(ftpm_virt_register_types)
