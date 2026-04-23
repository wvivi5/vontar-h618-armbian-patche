# Known Status

This repository captures a working local bring-up baseline for one validated
Vontar H618 unit and close H616-class variants.

## Current State

- Validated target: 4 GiB DDR3 Vontar H618 unit documented in
  `userpatches/VONTAR_H618_HARDWARE.md`
- Boot path target: microSD with project U-Boot/SPL
- Kernel line target: Armbian `current` and `edge` for the Vontar board file
- LAN bring-up depends on the matching U-Boot preinit sequence in this payload

## Boundaries

- This repository is for reproducible local builds and diagnostics.
- It is not a claim of upstream readiness for Linux, U-Boot, or Armbian.
- Firmware binaries are not distributed here.
- Other RAM sizes and board revisions are not yet fully validated.

## Before Upstreaming

- Split board-specific bring-up changes into reviewable topic series.
- Revalidate naming, bindings, and DTS structure against current upstream trees.
- Recheck redistribution and attribution requirements for any firmware payloads.
