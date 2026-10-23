#!/bin/bash
# ==============================================================================
# Script: registrar_boot_bios.sh
# Propósito: Gestionar la prioridad de arranque UEFI (GRUB vs OpenCore)
#            y evitar que OpenCore secuestre el orden de arranque de la BIOS.
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASKPASS="$DIR/setup.sh"
OCVALIDATE="$DIR/OpenCore-1.0.7-RELEASE/Utilities/ocvalidate/ocvalidate"

MODE="grub" # "grub" (default), "opencore", or "status"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --grub|--grub-first|--grub-default)
            MODE="grub"
            shift
            ;;
        --opencore|--oc-first|--opencore-first)
            MODE="opencore"
            shift
            ;;
        --status|-s)
            MODE="status"
            shift
            ;;
        --help|-h)
            echo "Uso: $0 [OPCIÓN]"
            echo ""
            echo "Opciones:"
            echo "  --grub, --grub-first      (Por defecto) Deja GRUB como arranque principal y"
            echo "                            desactiva LauncherOption para que OpenCore no tome control."
            echo "  --opencore, --oc-first    Configura OpenCore como arranque principal (LauncherOption=Full)."
            echo "  --status, -s              Muestra el estado actual de los cargadores y config.plist."
            echo "  --help, -h                Muestra esta ayuda."
            exit 0
            ;;
        *)
            echo "[!] Opción no reconocida: $1"
            echo "    Usa '$0 --help' para ver las opciones disponibles."
            exit 1
            ;;
    esac
done

echo "================================================================="
echo "   Gestor de Prioridad de Arranque UEFI (GRUB / OpenCore)        "
echo "================================================================="

# Preparar elevación de privilegios con askpass gráfico si está disponible
SUDO_CMD="sudo"
if [ -f "$ASKPASS" ]; then
    chmod +x "$ASKPASS"
    export SUDO_ASKPASS="$ASKPASS"
    SUDO_CMD="sudo -A"
fi

# ------------------------------------------------------------------------------
# 1. Localizar y montar la partición EFI de macOS / OpenCore
# ------------------------------------------------------------------------------
find_oc_efi() {
    local efi_mount=""
    if [ -d "/Volumes/NO NAME/EFI/OC" ]; then
        efi_mount="/Volumes/NO NAME"
    elif [ -d "/Volumes/EFI/EFI/OC" ]; then
        efi_mount="/Volumes/EFI"
    else
        for part in $(diskutil list | grep -i "EFI" | awk '{print $NF}'); do
            local mp=$(diskutil info "$part" 2>/dev/null | grep "Mount Point" | sed 's/.*Mount Point: *//')
            if [ -n "$mp" ] && [ -d "$mp/EFI/OC" ]; then
                efi_mount="$mp"
                break
            fi
        done
        if [ -z "$efi_mount" ]; then
            for part in $(diskutil list | grep -i "EFI" | awk '{print $NF}'); do
                $SUDO_CMD diskutil mount "$part" >/dev/null 2>&1 || true
                local mp=$(diskutil info "$part" 2>/dev/null | grep "Mount Point" | sed 's/.*Mount Point: *//')
                if [ -n "$mp" ] && [ -d "$mp/EFI/OC" ]; then
                    efi_mount="$mp"
                    break
                fi
            done
        fi
    fi
    echo "$efi_mount"
}

# ------------------------------------------------------------------------------
# 2. Localizar y montar la partición EFI de Linux / GRUB
# ------------------------------------------------------------------------------
find_grub_loader() {
    # Retorna: "MOUNT_POINT:LOADER_PATH"
    local candidates=(
        "EFI/fedora/shimx64.efi"
        "EFI/fedora/grubx64.efi"
        "EFI/ubuntu/shimx64.efi"
        "EFI/ubuntu/grubx64.efi"
        "EFI/arch/grubx64.efi"
        "EFI/debian/grubx64.efi"
        "EFI/gentoo/grubx64.efi"
        "EFI/BOOT/BOOTX64.EFI"
    )

    for part in $(diskutil list | grep -i "EFI" | awk '{print $NF}'); do
        local mp=$(diskutil info "$part" 2>/dev/null | grep "Mount Point" | sed 's/.*Mount Point: *//')
        if [ -z "$mp" ]; then
            $SUDO_CMD diskutil mount "$part" >/dev/null 2>&1 || true
            mp=$(diskutil info "$part" 2>/dev/null | grep "Mount Point" | sed 's/.*Mount Point: *//')
        fi

        if [ -n "$mp" ]; then
            # Asegurarnos de que no sea la partición de OpenCore pura (a menos que tenga grub)
            for cand in "${candidates[@]}"; do
                if [ -f "$mp/$cand" ]; then
                    # Si es EFI/BOOT/BOOTX64.EFI verificar que no sea OpenCore
                    if [ "$cand" = "EFI/BOOT/BOOTX64.EFI" ] && [ -d "$mp/EFI/OC" ]; then
                        continue
                    fi
                    echo "$mp:$cand"
                    return 0
                fi
            done
        fi
    done
    return 1
}

# ------------------------------------------------------------------------------
# 3. Función para actualizar LauncherOption en config.plist
# ------------------------------------------------------------------------------
set_launcher_option() {
    local target_val="$1"
    local efi_target="$2"

    python3 -c "
import re

def update_val(path, val):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        pattern = r'(<key>LauncherOption</key>\s*<string>)(.*?)(</string>)'
        if re.search(pattern, content):
            new_content = re.sub(pattern, r'\g<1>' + val + r'\g<3>', content)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print(f'    [OK] LauncherOption={val} configurado en: {path}')
        else:
            print(f'    [!] Advertencia: No se encontro LauncherOption en: {path}')
    except Exception as e:
        print(f'    [!] Error al actualizar {path}: {e}')

update_val('$DIR/EFI/OC/config.plist', '$target_val')
if '$efi_target' and '$efi_target/EFI/OC/config.plist' != '$DIR/EFI/OC/config.plist':
    update_val('$efi_target/EFI/OC/config.plist', '$target_val')
"
    if [ -x "$OCVALIDATE" ]; then
        "$OCVALIDATE" "$DIR/EFI/OC/config.plist" >/dev/null 2>&1 || true
    fi
}

# ------------------------------------------------------------------------------
# 4. Ejecución según el modo seleccionado
# ------------------------------------------------------------------------------
OC_EFI=$(find_oc_efi)
if [ -n "$OC_EFI" ]; then
    echo "[+] Particion EFI de OpenCore: $OC_EFI"
else
    echo "[!] Advertencia: No se encontro la particion EFI montada de OpenCore."
fi

GRUB_INFO=$(find_grub_loader || true)
GRUB_MOUNT=""
GRUB_LOADER=""
if [ -n "$GRUB_INFO" ]; then
    GRUB_MOUNT="${GRUB_INFO%%:*}"
    GRUB_LOADER="${GRUB_INFO#*:}"
    echo "[+] Particion EFI de GRUB: $GRUB_MOUNT ($GRUB_LOADER)"
fi

if [ "$MODE" = "status" ]; then
    echo ""
    echo "--- ESTADO ACTUAL DE ARRANQUE ---"
    CURRENT_VAL=$(grep -A 1 "<key>LauncherOption</key>" "$DIR/EFI/OC/config.plist" | grep "<string>" | sed -e 's/.*<string>//' -e 's/<\/string>.*//' | tr -d ' \t')
    echo "OpenCore LauncherOption: $CURRENT_VAL"
    if [ "$CURRENT_VAL" = "Full" ]; then
        echo "  -> ATENCION: Con 'Full', OpenCore toma prioridad 1 en la BIOS en cada arranque."
    elif [ "$CURRENT_VAL" = "Disabled" ]; then
        echo "  -> CORRECTO: Con 'Disabled', OpenCore respeta el orden de arranque de la BIOS."
    fi
    exit 0
fi

if [ "$MODE" = "grub" ]; then
    echo ""
    echo "[1/2] Desactivando LauncherOption en OpenCore para evitar conflicto con la BIOS..."
    set_launcher_option "Disabled" "$OC_EFI"

    echo ""
    echo "[2/2] Asignando GRUB como cargador principal en la NVRAM/BIOS..."
    if [ -n "$GRUB_MOUNT" ] && [ -n "$GRUB_LOADER" ]; then
        TARGET_FILE="$GRUB_MOUNT/$GRUB_LOADER"
        echo "[*] Notificando a la NVRAM con bless hacia: $TARGET_FILE"
        if $SUDO_CMD bless --mount "$GRUB_MOUNT" --file "$TARGET_FILE" --setBoot 2>/dev/null; then
            echo "[OK] GRUB registrado exitosamente en la NVRAM."
        else
            echo "[*] Nota: OpenCore mantiene protegida la NVRAM de macOS (RequestBootVarRouting=true)."
        fi
        echo "[OK] Al estar LauncherOption=Disabled, OpenCore no sobreescribira el orden de la BIOS."
    else
        echo "[!] No se encontro el archivo shimx64.efi o grubx64.efi en las particiones EFI montadas."
        echo "    OpenCore ha sido configurado en 'Disabled' para no tomar el control de la BIOS."
    fi

    sync

    echo ""
    echo "================================================================="
    echo " Configuracion finalizada exitosamente:"
    echo " 1. OpenCore LauncherOption = Disabled (no modificara la BIOS al iniciar)."
    echo " 2. GRUB permanece como el menu de inicio predeterminado."
    echo " 3. Flujo normal:"
    echo "    - Enciende la PC -> Aparece GRUB."
    echo "    - Selecciona macOS -> Inicia OpenCore y macOS."
    echo "    - Al reiniciar -> Regresas a GRUB sin perder la prioridad."
    echo "================================================================="
    exit 0
fi

if [ "$MODE" = "opencore" ]; then
    echo ""
    echo "[*] Configurando OpenCore como cargador principal (LauncherOption=Full)..."
    set_launcher_option "Full" "$OC_EFI"

    if [ -n "$OC_EFI" ] && [ -f "$OC_EFI/EFI/OC/OpenCore.efi" ]; then
        echo "[*] Registrando OpenCore en NVRAM con bless..."
        $SUDO_CMD bless --mount "$OC_EFI" --file "$OC_EFI/EFI/OC/OpenCore.efi" --setBoot || true
    fi

    sync

    echo ""
    echo "================================================================="
    echo " OpenCore configurado como cargador principal."
    echo "================================================================="
    exit 0
fi
