# SPDX-FileCopyrightText: 2025 NONE
#
# SPDX-License-Identifier: Unlicense

-include .env
export

.ONESHELL:

# Tools
CONTAINER_ENGINE ?= docker

# Directories
CACHE_DIR := $(CURDIR)/.cache
DATA_DIR := $(CACHE_DIR)/data
TMP_DIR := $(CACHE_DIR)/tmp

K0S_BM_BUTANE_PATH := $(CURDIR)/ignition/k0s-bm.bu
K0S_VM_BUTANE_PATH := $(CURDIR)/ignition/k0s-vm.bu

# CoreOS image builder
COREOS_ISO_PATH := $(TMP_DIR)/coreos.iso
COREOS_ISO_OUTPUT := coreos.iso
COREOS_VERSION := 42.20250901.3.0
TARGET_SYSTEM_ARCH := x86_64
COREOS_DOWNLOAD_URL := https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/$(COREOS_VERSION)/$(TARGET_SYSTEM_ARCH)
COREOS_ISO_URL := $(COREOS_DOWNLOAD_URL)/fedora-coreos-$(COREOS_VERSION)-live-iso.$(TARGET_SYSTEM_ARCH).iso
COREOS_KERNEL_URL := $(COREOS_DOWNLOAD_URL)/fedora-coreos-$(COREOS_VERSION)-live-kernel.$(TARGET_SYSTEM_ARCH)
COREOS_INITRAMFS_URL := $(COREOS_DOWNLOAD_URL)/fedora-coreos-$(COREOS_VERSION)-live-initramfs.$(TARGET_SYSTEM_ARCH).img
COREOS_ROOTFS_URL := $(COREOS_DOWNLOAD_URL)/fedora-coreos-$(COREOS_VERSION)-live-rootfs.$(TARGET_SYSTEM_ARCH).img

# Fedora Server image builder
FEDORA_VERSION := 42
FEDORA_DOWNLOAD_URL := https://download.fedoraproject.org/pub/fedora/linux/releases/$(FEDORA_VERSION)/Server/x86_64/os/images/pxeboot
FEDORA_KERNEL_URL := $(FEDORA_DOWNLOAD_URL)/vmlinuz
FEDORA_INITRD_URL := $(FEDORA_DOWNLOAD_URL)/initrd.img

# ARM image builder
ARM_INSTALL_RELEASE := 42
ARM_INSTALL_DEVICE := /dev/sda

# PXE artifacts
PXE_ROOT_DIR := containers/pxe-http/os
PXE_COREOS_DIR := $(PXE_ROOT_DIR)/fedora/coreos/$(COREOS_VERSION)/$(TARGET_SYSTEM_ARCH)
PXE_FEDORA_DIR := $(PXE_ROOT_DIR)/fedora/server/$(FEDORA_VERSION)/$(TARGET_SYSTEM_ARCH)
K0S_BM_IGNITION_OUTPUT := $(PXE_COREOS_DIR)/k0s-bm.ign
K0S_VM_IGNITION_OUTPUT := $(PXE_COREOS_DIR)/k0s-vm.ign
COREOS_KERNEL_OUTPUT := $(PXE_COREOS_DIR)/k0s-live-kernel
COREOS_INITRAMFS_OUTPUT := $(PXE_COREOS_DIR)/k0s-live-initramfs.img
COREOS_ROOTFS_OUTPUT := $(PXE_COREOS_DIR)/k0s-live-rootfs.img
FEDORA_KERNEL_OUTPUT := $(PXE_FEDORA_DIR)/vmlinuz
FEDORA_INITRD_OUTPUT := $(PXE_FEDORA_DIR)/initrd.img
CORE_IGNITION_PATH := $(PXE_COREOS_DIR)/core.ign
CORE_BUTANE_PATH := $(CURDIR)/ignition/core.bu
PKI_IGNITION_PATH := $(PXE_COREOS_DIR)/pki.ign
PKI_BUTANE_PATH := $(CURDIR)/ignition/pki.bu
STORAGE_IGNITION_PATH := $(PXE_COREOS_DIR)/storage.ign
STORAGE_BUTANE_PATH := $(CURDIR)/ignition/storage.bu

push-pxe-tftp-image: build-pxe-tftp-image
	$(CONTAINER_ENGINE) push "${CONTAINER_REGISTRY}/pxe-tftp:latest"
.PHONY: push-pxe-tftp-image

build-pxe-tftp-image:
	$(CONTAINER_ENGINE) build -t "${CONTAINER_REGISTRY}/pxe-tftp:latest" containers/pxe-tftp
.PHONY: build-pxe-tftp-image

push-pxe-http-image: build-pxe-http-image
	$(CONTAINER_ENGINE) push "${CONTAINER_REGISTRY}/pxe-http:latest"
.PHONY: push-pxe-http-image

build-pxe-http-image: coreos-generate-pxe
	$(CONTAINER_ENGINE) build -t "${CONTAINER_REGISTRY}/pxe-http:latest" containers/pxe-http
.PHONY: build-pxe-http-image

coreos-generate-pxe: k0s-generate-ignition core-generate-ignition pki-generate-ignition storage-generate-ignition ## Generate CoreOS PXE artifacts
	mkdir -p $(PXE_COREOS_DIR)
	curl -sSL -o "$(COREOS_KERNEL_OUTPUT)" "$(COREOS_KERNEL_URL)"
	curl -sSL -o "$(COREOS_ROOTFS_OUTPUT)" "$(COREOS_ROOTFS_URL)"
	if [ -f "$(COREOS_INITRAMFS_OUTPUT)" ]; then \
		rm "$(COREOS_INITRAMFS_OUTPUT)"; \
	fi
	coreos-installer pxe customize \
		--dest-console ttyS0,115200n8 \
		--dest-console tty0 \
		-o "$(COREOS_INITRAMFS_OUTPUT)" <(curl -sL $(COREOS_INITRAMFS_URL))
	chmod 0644 "$(COREOS_INITRAMFS_OUTPUT)"
.PHONY: coreos-generate-pxe

hypervisor-generate-pxe: ## Generate hypervisor PXE artifacts
	mkdir -p "$(PXE_FEDORA_DIR)"
	export install_device="/dev/nvme0n1" && \
	export labadm_passwd="$(LABADM_PASSWD)" && \
	mo "$(CURDIR)/kickstart/hypervisor.mustache" > "$(PXE_FEDORA_DIR)/hypervisor.ks"
	ksvalidator "$(PXE_FEDORA_DIR)/hypervisor.ks"
	curl -sSL -o "$(FEDORA_KERNEL_OUTPUT)" "$(FEDORA_KERNEL_URL)"
	curl -sSL -o "$(FEDORA_INITRD_OUTPUT)" "$(FEDORA_INITRD_URL)"
.PHONY: hypervisor-generate-pxe

core-arm-install: core-generate-ignition ## Install CoreOS on ARM device
	sudo env PATH="$(PATH)" coreos-installer install \
		-a aarch64 -s stable \
		-i "$(CORE_IGNITION_PATH)" \
		--append-karg nomodeset "$(ARM_INSTALL_DEVICE)"
	tmp="$$(mktemp -d)"; \
	mkdir -p "$${tmp}/boot/efi/"; \
	sudo dnf install -y \
		--downloadonly \
		--forcearch=aarch64 \
		--release="$(ARM_INSTALL_RELEASE)" \
		--destdir="$${tmp}" \
		uboot-images-armv8 bcm283x-firmware bcm283x-overlays; \
	for rpm in "$${tmp}"/*rpm; do \
		rpm2cpio "$${rpm}" | cpio -idv -D "$${tmp}"; \
	done; \
	mv "$${tmp}/usr/share/uboot/rpi_arm64/u-boot.bin" \
		"$${tmp}/boot/efi/rpi-u-boot.bin"; \
	part=$$( \
		lsblk "$(ARM_INSTALL_DEVICE)" -J -oLABEL,PATH  | \
		jq -r '.blockdevices[] | select(.label == "EFI-SYSTEM")'.path \
	); \
	mnt="$$(mktemp -d)"; \
	mkdir "$${mnt}"; \
	sudo mount "$${part}" "$${mnt}"; \
	sudo rsync -avh --ignore-existing "$${tmp}/boot/efi/" "$${mnt}"; \
	sudo umount "$${part}"; \
	rm -rf $${tmp}; \
	rm -rf $${mnt}
.PHONY: core-arm-install

k0s-generate-ignition:
	mkdir -p $$(dirname $(K0S_BM_IGNITION_OUTPUT))
	butane \
		--pretty --strict \
		--files-dir $(DATA_DIR) \
		< $(K0S_BM_BUTANE_PATH) \
		> $(K0S_BM_IGNITION_OUTPUT)
	mkdir -p $$(dirname $(K0S_VM_IGNITION_OUTPUT))
	butane \
		--pretty --strict \
		--files-dir $(DATA_DIR) \
		< $(K0S_VM_BUTANE_PATH) \
		> $(K0S_VM_IGNITION_OUTPUT)
.PHONY: k0s-generate-ignition

core-generate-ignition:
	mkdir -p $$(dirname $(CORE_IGNITION_PATH))
	butane \
		--pretty --strict \
		--files-dir $(DATA_DIR) \
		< $(CORE_BUTANE_PATH) \
		> $(CORE_IGNITION_PATH)
.PHONY: core-generate-ignition

pki-generate-ignition:
	mkdir -p $$(dirname $(PKI_IGNITION_PATH))
	butane \
		--pretty --strict \
		--files-dir $(DATA_DIR) \
		< $(PKI_BUTANE_PATH) \
		> $(PKI_IGNITION_PATH)
.PHONY: pki-generate-ignition

storage-generate-ignition:
	cp -r ./overlays $(DATA_DIR)
	mkdir -p $$(dirname $(STORAGE_IGNITION_PATH))
	butane \
		--pretty --strict \
		--files-dir $(DATA_DIR) \
		< $(STORAGE_BUTANE_PATH) \
		> $(STORAGE_IGNITION_PATH)
.PHONY: pki-generate-ignition

coreos-generate-iso:
	mkdir -p "$(TMP_DIR)"
	curl -sSL -o "$(COREOS_ISO_PATH)" "$(COREOS_ISO_URL)"
	coreos-installer iso customize \
		--dest-console ttyS0,115200n8 \
		--dest-console tty0 \
		-o $(COREOS_ISO_OUTPUT) $(COREOS_ISO_PATH)
.PHONY: coreos-generate-iso

clean: ## Clean generated files
	rm -rf $(CACHE_DIR)
	rm -f $(COREOS_ISO_OUTPUT)
.PHONY: clean

reuse-apply:
	reuse annotate --copyright NONE --license Unlicense -r "$(PROJECT_ROOT)" --fallback-dot-license
.PHONY: reuse-apply
