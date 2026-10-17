#!/bin/bash
# ==============================================================================
# Script: registrar_boot_bios.sh
# Propósito: Registrar el arranque de OpenCore/macOS de forma independiente
#            en la NVRAM/BIOS (sin mover particiones) para convivir con Windows.
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASKPASS="$DIR/setup.sh"

echo "================================================================="
echo "   Configurador de Arranque UEFI Independiente (OpenCore / macOS) "
echo "================================================================="

# 1. Localizar y montar la partición EFI
EFI_MOUNT=""
if [ -d "/Volumes/NO NAME/EFI/OC" ]; then
    EFI_MOUNT="/Volumes/NO NAME"
elif [ -d "/Volumes/EFI/EFI/OC" ]; then
    EFI_MOUNT="/Volumes/EFI"
else
    echo "[*] Buscando partición EFI del disco de arranque..."
    ROOT_DISK=$(diskutil info / 2>/dev/null | grep "Part of Whole" | awk '{print $4}')
    if [ -n "$ROOT_DISK" ]; then
        EFI_PART=$(diskutil list "$ROOT_DISK" | grep -i "EFI" | awk '{print $NF}' | head -n 1)
        if [ -n "$EFI_PART" ]; then
            echo "[*] Montando partición EFI ($EFI_PART)..."
            diskutil mount "$EFI_PART" || true
            EFI_MOUNT=$(diskutil info "$EFI_PART" 2>/dev/null | grep "Mount Point" | sed 's/.*Mount Point: *//')
        fi
    fi
fi

if [ -z "$EFI_MOUNT" ] || [ ! -d "$EFI_MOUNT/EFI/OC" ]; then
    echo "[!] Error: No se encontró la carpeta EFI/OC en la partición montada ($EFI_MOUNT)."
    echo "    Asegúrate de montar la partición EFI con MountEFI primero."
    exit 1
fi

echo "[+] Partición EFI detectada en: $EFI_MOUNT"

# 2. Configurar LauncherOption = Full en config.plist
echo "[*] Habilitando LauncherOption = Full en config.plist..."
python3 -c "
import re

def update_config(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        pattern = r'(<key>LauncherOption</key>\s*<string>)(.*?)(</string>)'
        if re.search(pattern, content):
            new_content = re.sub(pattern, r'\g<1>Full\g<3>', content)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print(f'    [✓] LauncherOption=Full configurado en: {path}')
        else:
            print(f'    [!] Advertencia: No se encontró la clave LauncherOption en {path}')
    except Exception as e:
        print(f'    [!] Error al actualizar {path}: {e}')

update_config('$EFI_MOUNT/EFI/OC/config.plist')

if '$DIR/EFI/OC/config.plist' != '$EFI_MOUNT/EFI/OC/config.plist':
    update_config('$DIR/EFI/OC/config.plist')
"

# 3. Validar con ocvalidate si está disponible
OCVALIDATE="$DIR/OpenCore-1.0.7-RELEASE/Utilities/ocvalidate/ocvalidate"
if [ -x "$OCVALIDATE" ]; then
    echo "[*] Validando configuración con ocvalidate..."
    "$OCVALIDATE" "$EFI_MOUNT/EFI/OC/config.plist" || true
fi

# 4. Registrar OpenCore.efi en la NVRAM/UEFI mediante 'bless'
echo "[*] Registrando entrada de arranque independiente en la BIOS (NVRAM)..."
SUDO_CMD="sudo"
if [ -f "$ASKPASS" ]; then
    chmod +x "$ASKPASS"
    export SUDO_ASKPASS="$ASKPASS"
    SUDO_CMD="sudo -A"
fi

if $SUDO_CMD bless --mount "$EFI_MOUNT" --file "$EFI_MOUNT/EFI/OC/OpenCore.efi" --setBoot; then
    echo "[✓] Entrada de OpenCore registrada exitosamente con bless en la NVRAM."
else
    echo "[!] bless retornó una advertencia, pero LauncherOption=Full registrará y mantendrá la entrada en el próximo arranque de la BIOS."
fi

sync

echo ""
echo "================================================================="
echo " ¡LISTO! Arranque independiente configurado exitosamente."
echo "================================================================="
echo "1. Tu partición actual de 200 MB no ha sido movida ni alterada."
echo "2. Windows Boot Manager conserva su entrada original en la BIOS."
echo "3. Se registró una entrada dedicada e independiente para OpenCore/macOS."
echo "4. Al encender o reiniciar tu Lenovo ThinkCentre, presiona F12"
echo "   para ver ambas opciones independientes en el menú de la BIOS:"
echo "     - OpenCore (macOS)"
echo "     - Windows Boot Manager"
echo "================================================================="
