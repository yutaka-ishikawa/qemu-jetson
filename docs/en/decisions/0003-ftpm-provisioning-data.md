# 0003: Provisioning data for B2 validation

[日本語](../../decisions/0003-ftpm-provisioning-data.md) | English

Status: awaiting the user's decision. B2 is approved; integrating its PTA proceeds.

Beyond readiness notification, the full NVIDIA helper PTA consumes a Firmware ID key/certificate,
fTPM seed, SN, EPS seed, and either EK certificates or a SID certificate with EK CSRs.
Execution tests involving these keys and certificates require selecting the data source.

| Alternative | Benefits | Limitations |
| --- | --- | --- |
| Generate a QEMU-only test CA and virtual-device keys/certificates (recommended) | Reproducible inputs for actual signing/verification and certificate API tests | No trust as NVIDIA or physical-device manufacturing certificates; label as test-only |
| Use the user's existing keys, certificates and provisioning data | Test consistency with existing data and certificate chains | Requires supplied inputs and consistency with the virtual SN, seeds and keys |

Do not generate a test CA or Firmware ID private key before the decision.
PTA compilation, virtual platform integration, and handoff format/bounds validation proceed independently.
