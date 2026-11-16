# Project instructions

- Use English filenames throughout this repository.
- Maintain project documentation in Japanese and English.
- Push completed changes directly to `main`; do not open pull requests.
- When material development alternatives arise, present their benefits, limitations, and recommendation to the user and obtain their decision before implementing the dependent work.
- Document the alternatives and user decision in both languages and push that record. See `docs/decisions/0001-ftpm-execution-path.md`.
- Continue the approved option-B path with B2: integrate the complete NVIDIA helper PTA, not a PING_NS-only replacement. Keep the existing T234 hardware profile available.
- The source of B2 key/certificate validation data is pending decision 0003. Do not generate a test CA or Firmware ID private key before the user chooses.
- Keep generated device secrets, disk images, and build outputs out of Git.
