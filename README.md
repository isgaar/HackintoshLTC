# HackintoshLTC - Lenovo ThinkCentre M75s Gen 2 (macOS Sequoia 15)

Configuración de **OpenCore 1.0.7** optimizada y probada para ejecutar **macOS Sequoia (15)** en hardware AMD Ryzen Zen 3 con gráficos integrados Radeon Vega (Cezanne).

```bash
git clone --recurse-submodules https://github.com/isgaar/HackintoshLTC.git
```

---

## 📦 Clonado con Dependencias Profundas (Submódulos)

Para clonar este repositorio con todas sus herramientas y dependencias automáticamente:

```bash
git clone --recurse-submodules https://github.com/isgaar/HackintoshLTC.git
```

Si ya has clonado el repositorio de forma simple, puedes inicializar y descargar todas las dependencias con:

```bash
git submodule update --init --recursive
```

### Dependencias y Herramientas Integradas:
- **`Hardware-Sniffer/`** ([lzhoang2801/Hardware-Sniffer](https://github.com/lzhoang2801/Hardware-Sniffer)): Submódulo Git para la detección automática y reporte de hardware del equipo.
- **`OpCore-Simplify/`** ([lzhoang2801/OpCore-Simplify](https://github.com/lzhoang2801/OpCore-Simplify)): Submódulo Git para la simplificación de ACPI y generación de OpenCore.
- **`OpenCore-1.0.7-RELEASE/`**: Binarios oficiales y utilidades (`macrecovery.py`, `macserial`, `ocvalidate`, etc.).

---

## 💻 Especificaciones de Hardware

| Componente | Detalle del Hardware | Soporte en macOS |
| :--- | :--- | :--- |
| **Equipo** | Lenovo ThinkCentre M75s Gen 2 (11R7S0MU00) | Compatible UEFI |
| **Procesador** | AMD Ryzen 5 5600G (Cezanne / Zen 3, 6 núcleos / 12 hilos) | Parches de Kernel AMD Zen 3 (19h) |
| **Gráficos (iGPU)** | AMD Radeon Vega Graphics (1002:1638) | Aceleración Metal completa con `NootedRed.kext` |
| **Audio** | Realtek ALC623 (10EC:0623) | `AppleALC.kext` (layout-id: 13 / alcid=13) |
| **Ethernet** | Realtek RTL8111/8168 Gigabit Ethernet | `RealtekRTL8111.kext` |
| **Wi-Fi** | Intel Dual Band Wireless-AC 9260 (8086:2526) | `itlwm.kext` + HeliPort.app |
| **Bluetooth** | Intel Wireless-AC 9260 Bluetooth (8087:0025) | `IntelBluetoothFirmware.kext` + `BlueToolFixup.kext` |
| **Almacenamiento** | NVMe Western Digital SN540 / SN350 | `NVMeFix.kext` |
| **SMBIOS** | `MacPro7,1` firmado con `macserial` | Compatible de forma nativa con macOS 15 Sequoia |

---

## 🚀 Grabado del Instalador USB en Linux

El repositorio incluye el script `crear_usb_instalador.sh`, el cual sigue las directrices oficiales de **Dortania OpenCore Install Guide para Linux**.

### Pasos:

1. Conecta tu memoria USB (mínimo 4 GB).
2. Da permisos de ejecución al script (ya incluidos):
   ```bash
   chmod +x crear_usb_instalador.sh
   ```
3. Ejecuta el script:
   ```bash
   ./crear_usb_instalador.sh
   ```
4. El script:
   - Inicializará automáticamente los submódulos si no estaban clonados.
   - Detectará automáticamente las unidades USB conectadas.
   - Formateará la memoria en **GPT** y partición **FAT32** con etiqueta `OPENCORE`.
   - Copiará la carpeta `EFI` y los archivos de recuperación de **macOS Sequoia** (`com.apple.recovery.boot/BaseSystem.dmg`).
   - Sincronizará y desmontará de forma segura el dispositivo.

---

## ⚙️ Ajustes Recomendados en la BIOS/UEFI

Antes de arrancar desde el USB:

* **Desactivar:**
  * Fast Boot
  * Secure Boot
  * CSM (Compatibility Support Module)
  * Serial/COM Port
* **Activar:**
  * Above 4G Decoding
  * EHCI/XHCI Hand-off
  * SATA Mode: AHCI
  * UEFI Boot Mode Only
  * **UMA Framebuffer Size / VRAM iGPU:** Asignar al menos 512 MB o 1 GB / 2 GB en BIOS para el rendimiento óptimo de NootedRed.

---

## 📁 Estructura del USB resultante

```text
USB/
├── EFI/
│   ├── BOOT/
│   │   └── BOOTx64.efi
│   └── OC/
│       ├── ACPI/
│       ├── Drivers/
│       ├── Kexts/
│       ├── OpenCore.efi
│       └── config.plist
└── com.apple.recovery.boot/
    ├── BaseSystem.chunklist
    └── BaseSystem.dmg
```

---

## 🍺 Instalación de Homebrew en macOS Sequoia (x86_64)

Dado que las versiones más recientes del script principal de Homebrew restringen la instalación automática oficial a Apple Silicon, se incluye el script asistente gráfico `apple_askpass.sh` para solicitar permisos de administrador mediante una ventana nativa de macOS ("polkit") y completar la configuración de `/usr/local`:

```bash
chmod +x apple_askpass.sh
SUDO_ASKPASS="$(pwd)/apple_askpass.sh" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/df3c2556141c012eaba0453ede7a1bd4f05b824c/install.sh)"
```

---

## 🪟 Arranque Independiente en la BIOS (Dual Boot con Windows)

Para registrar OpenCore como una entrada UEFI dedicada en la BIOS de tu Lenovo ThinkCentre (de modo que en el menú `F12` aparezcan de forma independiente tanto **OpenCore** como **Windows Boot Manager** sin mover ni crear particiones adicionales):

```bash
chmod +x registrar_boot_bios.sh
./registrar_boot_bios.sh
```

Este script activa `LauncherOption = Full`, valida la configuración con `ocvalidate` y registra el cargador directamente en la NVRAM/UEFI mediante `bless`.


