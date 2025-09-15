<!--
SPDX-FileCopyrightText: 2025 NONE

SPDX-License-Identifier: Unlicense
-->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains infrastructure automation for building and deploying homelab OS images using Fedora CoreOS and traditional Fedora Server. The project generates PXE boot artifacts, ignition configurations, and ISO images for automated OS deployment across different hardware configurations including bare metal k0s clusters, VMs, hypervisors, and PKI infrastructure.

## Development Environment

The project uses Nix Flakes for development environment management:

```bash
# Enter development shell (requires Nix with flakes enabled)
nix develop

# Or if using direnv
direnv allow
```

The development shell includes all necessary tools: butane, coreos-installer, curl, make, podman, pre-commit, mo (mustache), and others.

## Core Architecture

### Directory Structure
- `ignition/` - Butane configuration files (*.bu) that generate Ignition configs for CoreOS
  - `core.bu` - Base CoreOS configuration 
  - `k0s-bm.bu` - k0s bare metal node configuration
  - `k0s-vm.bu` - k0s virtual machine configuration
  - `pki.bu` - PKI infrastructure configuration
- `kickstart/` - Kickstart templates for traditional Fedora Server installation
  - `hypervisor.mustache` - Mustache template for hypervisor installation
- `overlays/` - File overlays organized by deployment type (core, coreos, k0s, pki)
  - Contains systemd services, configuration files, and other OS customizations

### Build System

The project uses GNU Make with clearly defined targets. Key variables are configured at the top of the Makefile:

- `COREOS_VERSION` - Controls which CoreOS version to use
- `FEDORA_VERSION` - Controls which Fedora Server version to use  
- `TARGET_SYSTEM_ARCH` - Target architecture (x86_64)
- `CONTAINER_ENGINE` - Container runtime (docker/podman)

## Common Commands

### Generate PXE Boot Artifacts
```bash
# Generate all CoreOS PXE artifacts (kernels, initramfs, rootfs, ignition configs)
make coreos-generate-pxe

# Generate Fedora Server PXE artifacts for hypervisor installation
make hypervisor-generate-pxe
```

### Generate Individual Ignition Configs
```bash
# Generate k0s ignition files (both bare metal and VM variants)
make k0s-generate-ignition

# Generate core ignition file
make core-generate-ignition

# Generate PKI ignition file  
make pki-generate-ignition
```

### ARM Installation
```bash
# Install CoreOS on ARM device (requires ARM_INSTALL_DEVICE variable)
make core-arm-install
```

### Other Operations
```bash
# Generate CoreOS ISO
make coreos-generate-iso

# Clean all generated artifacts
make clean

# Apply REUSE licensing headers
make reuse-apply
```

### Pre-commit Hooks
```bash
# Install pre-commit hooks
pre-commit install

# Run pre-commit on all files
pre-commit run --all-files
```

## Required Environment Variables

Several targets require environment variables to be set:

- `LABADM_PUBLIC_KEY` - Path to public SSH key for labadm user
- `LABADM_PASSWD` - Password hash for labadm user (used in kickstart)
- `ARM_INSTALL_DEVICE` - Target device for ARM installation (default: /dev/sda)

These can be set in a `.env` file in the project root, which will be automatically loaded by Make.

## Configuration Workflow

1. **Butane to Ignition**: Butane files (*.bu) are compiled to Ignition JSON configs using the `butane` tool
2. **Overlay Integration**: The `overlays/` directory structure is copied to a staging area and referenced by Butane configs
3. **Template Processing**: Kickstart templates use Mustache for variable substitution
4. **Artifact Generation**: Final artifacts are placed in `.cache/data/os/` following a structured path convention

## Output Structure

Generated artifacts follow this structure:
```
.cache/data/os/
├── fedora/
│   ├── coreos/[VERSION]/[ARCH]/
│   │   ├── *.ign (ignition configs)
│   │   ├── k0s-live-kernel
│   │   ├── k0s-live-initramfs.img
│   │   └── k0s-live-rootfs.img
│   └── server/[VERSION]/[ARCH]/
│       ├── hypervisor.ks
│       ├── vmlinuz
│       └── initrd.img
```

## Code Quality

The project enforces code quality through:
- Pre-commit hooks for formatting, linting, and security scanning
- REUSE compliance for licensing headers
- Kickstart validation using `ksvalidator`
- Butane strict mode compilation