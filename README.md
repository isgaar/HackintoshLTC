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
- **Audio:** Realtek ALC623 (alcid=13, EAPD habilitado)
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

## Gestión de Prioridad de Arranque UEFI (GRUB / OpenCore)

Para evitar que OpenCore secuestre el orden de arranque de la BIOS y mantener GRUB como gestor principal por defecto:

```bash
chmod +x registrar_boot_bios.sh
./registrar_boot_bios.sh
```

Opciones:
- `./registrar_boot_bios.sh` o `./registrar_boot_bios.sh --grub` (mantiene a GRUB en primer lugar y configura `LauncherOption=Disabled`).
- `./registrar_boot_bios.sh --opencore` (asigna a OpenCore como prioridad en BIOS).
- `./registrar_boot_bios.sh --status` (muestra el estado actual de los cargadores y OpenCore).

---

## Instalación de Homebrew (x86_64)

Para instalar Homebrew en macOS Sequoia x86_64 con elevación gráfica:

```bash
chmod +x setup.sh
./setup.sh --brew
```

---

## Configuración Post-Instalación (Wi-Fi, Teclado y Askpass)

Para configurar automáticamente HeliPort (Wi-Fi Intel), remapear las teclas Ctrl y Super/Windows para atajos habituales de PC e integrar el asistente gráfico:

```bash
chmod +x setup.sh
./setup.sh
```

Opciones adicionales:
- `./setup.sh --brew` (instalar Homebrew para arquitectura x86_64).
- `./setup.sh --revert-keyboard` (restaurar mapeo de teclado original).
- `./setup.sh --keyboard-only` (aplicar únicamente el parche de teclado).
- `./setup.sh --wifi-only` (configurar únicamente el Wi-Fi).

