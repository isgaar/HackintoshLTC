#!/usr/bin/env bash
# ==============================================================================
# Script de Preparación y Grabado de Instalador macOS para Hackintosh (OpenCore)
# Sigue las directrices oficiales de Dortania OpenCore Install Guide para Linux
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EFI_DIR="${SCRIPT_DIR}/EFI"
RECOVERY_DIR=""
MOUNT_DIR=""

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

cleanup() {
    if [[ -n "${MOUNT_DIR:-}" ]] && mountpoint -q "${MOUNT_DIR}" 2>/dev/null; then
        info "Desmontando punto temporal ${MOUNT_DIR}..."
        sync
        sudo umount "${MOUNT_DIR}" || true
        rmdir "${MOUNT_DIR}" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

print_banner() {
    echo -e "${BLUE}${BOLD}"
    echo "=================================================================="
    echo "     Instalador OpenCore macOS Sequoia / Recovery en Linux       "
    echo "       Siguiendo Dortania OpenCore Linux Install Guide           "
    echo "=================================================================="
    echo -e "${NC}"
}

check_dependencies() {
    local missing=()
    for cmd in lsblk parted mkfs.vfat sync rsync; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Faltan utilidades requeridas en el sistema: ${missing[*]}"
        echo "En Fedora/RHEL: sudo dnf install dosfstools parted util-linux rsync"
        echo "En Debian/Ubuntu: sudo apt-get install dosfstools parted util-linux rsync"
        exit 1
    fi
}

locate_recovery_files() {
    info "Buscando archivos de recuperación de macOS (BaseSystem.dmg)..."
    
    local possible_paths=(
        "${SCRIPT_DIR}/OpenCore-1.0.7-RELEASE/Utilities/macrecovery/com.apple.recovery.boot"
        "${SCRIPT_DIR}/com.apple.recovery.boot"
        "${SCRIPT_DIR}/macrecovery/com.apple.recovery.boot"
    )

    for p in "${possible_paths[@]}"; do
        if [[ -f "${p}/BaseSystem.dmg" && -f "${p}/BaseSystem.chunklist" ]]; then
            RECOVERY_DIR="$p"
            success "Archivos de recuperación encontrados en: ${RECOVERY_DIR}"
            return 0
        fi
    done

    # Si no se encuentra, buscar en el repositorio
    local found_dmg
    found_dmg="$(find "${SCRIPT_DIR}" -name "BaseSystem.dmg" -print -quit 2>/dev/null || true)"
    if [[ -n "$found_dmg" ]]; then
        RECOVERY_DIR="$(dirname "$found_dmg")"
        if [[ -f "${RECOVERY_DIR}/BaseSystem.chunklist" ]]; then
            success "Archivos de recuperación encontrados en: ${RECOVERY_DIR}"
            return 0
        fi
    fi

    warn "No se encontraron los archivos de recuperación en las ubicaciones habituales."
    local macrecovery_script="${SCRIPT_DIR}/OpenCore-1.0.7-RELEASE/Utilities/macrecovery/macrecovery.py"
    
    if [[ -f "$macrecovery_script" ]]; then
        echo -e "¿Deseas descargar la imagen de recuperación de macOS Sequoia ahora usando macrecovery.py? (s/N): "
        read -r resp
        if [[ "$resp" =~ ^[sSyY]$ ]]; then
            info "Descargando imagen de macOS Sequoia (Mac-7BA5B2D9E42DDD94)..."
            (
                cd "$(dirname "$macrecovery_script")"
                python3 ./macrecovery.py -b Mac-7BA5B2D9E42DDD94 -m 00000000000000000 download
            )
            RECOVERY_DIR="$(dirname "$macrecovery_script")/com.apple.recovery.boot"
            if [[ -f "${RECOVERY_DIR}/BaseSystem.dmg" ]]; then
                success "Descarga completada correctamente."
                return 0
            fi
        fi
    fi

    error "No se pudo localizar 'com.apple.recovery.boot' con BaseSystem.dmg y BaseSystem.chunklist."
    exit 1
}

validate_efi_dir() {
    info "Validando directorio EFI en: ${EFI_DIR}..."
    if [[ ! -d "${EFI_DIR}" ]]; then
        error "No se encuentra el directorio EFI en ${EFI_DIR}."
        exit 1
    fi

    if [[ ! -f "${EFI_DIR}/BOOT/BOOTx64.efi" ]]; then
        error "Falta ${EFI_DIR}/BOOT/BOOTx64.efi."
        exit 1
    fi

    if [[ ! -f "${EFI_DIR}/OC/config.plist" ]]; then
        error "Falta ${EFI_DIR}/OC/config.plist."
        exit 1
    fi

    # Validación con ocvalidate si existe
    local ocvalidate_bin="${SCRIPT_DIR}/OpenCore-1.0.7-RELEASE/Utilities/ocvalidate/ocvalidate.linux"
    if [[ -x "$ocvalidate_bin" ]]; then
        info "Ejecutando verificación con ocvalidate..."
        if "$ocvalidate_bin" "${EFI_DIR}/OC/config.plist" &>/dev/null; then
            success "El archivo config.plist ha pasado la validación de OpenCore sin errores."
        else
            warn "ocvalidate reportó advertencias en config.plist. Por favor revisa su configuración."
        fi
    fi
}

list_usb_disks() {
    echo -e "\n${BOLD}Unidades USB extraíbles detectadas:${NC}"
    echo "------------------------------------------------------------------"
    lsblk -d -o NAME,SIZE,MODEL,TRAN,RM,HOTPLUG | grep -E "usb|NAME" || true
    echo "------------------------------------------------------------------"
}

is_system_partition() {
    local target="$1"
    local mounts
    mounts="$(lsblk -no MOUNTPOINT "$target" 2>/dev/null | grep -v '^$' || true)"
    for m in $mounts; do
        if [[ "$m" == "/" || "$m" == "/boot" || "$m" == "/home" || "$m" == "/boot/efi" || "$m" == "/etc" ]]; then
            return 0
        fi
    done
    return 1
}

select_target_disk() {
    list_usb_disks
    
    echo -e "\n${YELLOW}Introduce el identificador del disco USB a preparar (ejemplo: sdb):${NC} "
    read -r chosen_dev

    chosen_dev="${chosen_dev#/dev/}" # Quitar /dev/ si fue escrito

    if [[ -z "$chosen_dev" ]]; then
        error "No se especificó ningún dispositivo."
        exit 1
    fi

    TARGET_DEV="/dev/${chosen_dev}"

    if [[ ! -b "$TARGET_DEV" ]]; then
        error "El dispositivo ${TARGET_DEV} no existe o no es un dispositivo de bloques."
        exit 1
    fi

    # Comprobación de seguridad: asegurarse de no tocar particiones de sistema
    if is_system_partition "$TARGET_DEV"; then
        error "¡SEGURIDAD! ${TARGET_DEV} contiene puntos de montaje del sistema raíz/home. Abortando."
        exit 1
    fi

    local dev_type
    dev_type="$(lsblk -no TYPE "$TARGET_DEV" 2>/dev/null | head -n1 || true)"
    if [[ "$dev_type" != "disk" ]]; then
        error "Debes seleccionar un disco completo (tipo 'disk', ej: /dev/sdb), no una partición individual."
        exit 1
    fi

    echo -e "\n${RED}${BOLD}¡ATENCIÓN! TODOS LOS DATOS EN ${TARGET_DEV} SERÁN BORRADOS POR COMPLETO.${NC}"
    lsblk "$TARGET_DEV" -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
    echo -e "\nPara confirmar, escribe '${BOLD}SI${NC}': "
    read -r confirm
    if [[ "$confirm" != "SI" && "$confirm" != "si" && "$confirm" != "Si" ]]; then
        info "Operación cancelada por el usuario."
        exit 0
    fi
}

format_usb() {
    info "Desmontando cualquier partición activa en ${TARGET_DEV}..."
    local parts
    parts="$(lsblk -lno NAME "$TARGET_DEV" | tail -n +2 || true)"
    for p in $parts; do
        sudo umount "/dev/${p}" 2>/dev/null || true
    done

    info "Creando tabla de particiones GPT en ${TARGET_DEV}..."
    sudo parted -s "$TARGET_DEV" mklabel gpt

    info "Creando partición primaria FAT32 (100% del disco)..."
    sudo parted -s "$TARGET_DEV" mkpart primary fat32 1MiB 100%
    sudo parted -s "$TARGET_DEV" set 1 esp on || sudo parted -s "$TARGET_DEV" set 1 boot on || true

    # Esperar a que el kernel registre la nueva partición
    info "Sincronizando particiones con el kernel..."
    sleep 2
    sudo partprobe "$TARGET_DEV" 2>/dev/null || true
    sleep 2

    # Determinar nombre de la partición (ej: sdb1 o nvme0n1p1)
    if [[ "$TARGET_DEV" =~ [0-9]$ ]]; then
        TARGET_PART="${TARGET_DEV}p1"
    else
        TARGET_PART="${TARGET_DEV}1"
    fi

    if [[ ! -b "$TARGET_PART" ]]; then
        error "No se encontró la partición creada: ${TARGET_PART}"
        exit 1
    fi

    info "Formateando partición ${TARGET_PART} como FAT32 (etiqueta: OPENCORE)..."
    sudo mkfs.vfat -F 32 -n "OPENCORE" "$TARGET_PART"
    success "Partición formateada con éxito."
}

copy_files() {
    MOUNT_DIR="$(mktemp -d /tmp/hackintosh_usb_XXXXXX)"
    info "Montando ${TARGET_PART} en ${MOUNT_DIR}..."
    sudo mount "$TARGET_PART" "$MOUNT_DIR"

    info "Copiando carpeta EFI a la raíz del USB..."
    sudo cp -r "${EFI_DIR}" "${MOUNT_DIR}/EFI"

    info "Copiando carpeta com.apple.recovery.boot a la raíz del USB..."
    sudo cp -r "${RECOVERY_DIR}" "${MOUNT_DIR}/com.apple.recovery.boot"

    info "Asegurando permisos y sincronizando datos al disco (sync)... Esto puede tardar unos momentos..."
    sync

    info "Verificando estructura de archivos en el USB..."
    local check_failed=0
    [[ -f "${MOUNT_DIR}/EFI/BOOT/BOOTx64.efi" ]] || check_failed=1
    [[ -f "${MOUNT_DIR}/EFI/OC/config.plist" ]] || check_failed=1
    [[ -f "${MOUNT_DIR}/com.apple.recovery.boot/BaseSystem.dmg" ]] || check_failed=1
    [[ -f "${MOUNT_DIR}/com.apple.recovery.boot/BaseSystem.chunklist" ]] || check_failed=1

    if [[ $check_failed -eq 0 ]]; then
        success "Estructura de archivos verificada correctamente:"
        echo "  • ${MOUNT_DIR}/EFI/BOOT/BOOTx64.efi"
        echo "  • ${MOUNT_DIR}/EFI/OC/config.plist"
        echo "  • ${MOUNT_DIR}/com.apple.recovery.boot/BaseSystem.dmg"
        echo "  • ${MOUNT_DIR}/com.apple.recovery.boot/BaseSystem.chunklist"
    else
        error "Hubo un error en la verificación de archivos en el USB."
        exit 1
    fi

    info "Desmontando USB de forma segura..."
    sudo umount "${MOUNT_DIR}"
    rmdir "${MOUNT_DIR}" 2>/dev/null || true
    MOUNT_DIR=""
    success "¡El instalador USB de OpenCore está listo para usar!"
}

show_post_instructions() {
    echo -e "\n${GREEN}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}           ¡GRABADO COMPLETADO CON ÉXITO!                         ${NC}"
    echo -e "${GREEN}${BOLD}==================================================================${NC}"
    echo -e "Tu memoria USB está configurada con:"
    echo -e "  - OpenCore 1.0.7 con parches AMD Zen 3 (Ryzen 5 5600G)"
    echo -e "  - Kext NootedRed para aceleración de gráficos integrados Vega"
    echo -e "  - Instalador Recovery de macOS Sequoia (15)"
    echo -e "  - SMBIOS MacPro7,1 firmado con macserial y UUID de hardware"
    echo ""
    echo -e "${YELLOW}${BOLD}Recomendaciones de configuración de BIOS para AMD Hackintosh:${NC}"
    echo -e "  [x] ${BOLD}Desactivar:${NC} Fast Boot, Secure Boot, CSM (Compatibility Support Module), Serial Port"
    echo -e "  [x] ${BOLD}Activar:${NC} Above 4G Decoding, EHCI/XHCI Hand-off, SATA Mode: AHCI, UEFI Boot Only"
    echo -e "  [x] ${BOLD}Memoria VRAM:${NC} En BIOS, asignar al menos 512MB o 1GB/2GB a la GPU integrada (UMA Framebuffer Size)"
    echo -e "==================================================================\n"
}

main() {
    print_banner
    check_dependencies
    validate_efi_dir
    locate_recovery_files
    select_target_disk
    format_usb
    copy_files
    show_post_instructions
}

main "$@"
