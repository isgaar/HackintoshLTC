# HackintoshLTC - Lenovo ThinkCentre M75s Gen 2

Configuración de OpenCore para Lenovo ThinkCentre M75s Gen 2 (AMD Ryzen 5 5600G) en macOS Sequoia (15).

```bash
git clone --recurse-submodules https://github.com/isgaar/HackintoshLTC.git
```

---

## Clonado

Para clonar con submódulos:

```bash
git clone --recurse-submodules https://github.com/isgaar/HackintoshLTC.git
```

O si ya se clonó sin submódulos:

```bash
git submodule update --init --recursive
```

---

## Hardware

- **Equipo:** Lenovo ThinkCentre M75s Gen 2
- **CPU / iGPU:** AMD Ryzen 5 5600G (Radeon Vega)
- **Audio:** Realtek ALC623 (alcid=21)
- **Ethernet:** Realtek RTL8111
- **Wi-Fi / BT:** Intel Wireless-AC 9260

---

## Grabado del Instalador USB en Linux

```bash
chmod +x crear_usb_instalador.sh
./crear_usb_instalador.sh
```

El script formatea la memoria USB en FAT32/GPT e instala la EFI junto a los archivos de recuperación de macOS Sequoia.

---

## Ajustes en BIOS/UEFI

* **Desactivar:** Fast Boot, Secure Boot, CSM, Serial/COM Port.
* **Activar:** Above 4G Decoding, EHCI/XHCI Hand-off, SATA Mode: AHCI, UEFI Only, UMA Framebuffer (1 GB o 2 GB).

---

## Arranque Independiente en BIOS (Dual Boot)

Para registrar OpenCore en la NVRAM de la BIOS de forma independiente a Windows Boot Manager sin alterar particiones:

```bash
chmod +x registrar_boot_bios.sh
./registrar_boot_bios.sh
```

---

## Instalación de Homebrew (x86_64)

Para instalar Homebrew en macOS Sequoia x86_64 con elevación gráfica:

```bash
chmod +x apple_askpass.sh
SUDO_ASKPASS="$(pwd)/apple_askpass.sh" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/df3c2556141c012eaba0453ede7a1bd4f05b824c/install.sh)"
```
