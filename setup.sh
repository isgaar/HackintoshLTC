#!/bin/bash
# ==============================================================================
# Script: setup.sh (HackintoshLTC Post-Install Setup)
# Descripción: Automatiza la configuración esencial post-instalación:
#   1. Asistente gráfico de elevación (Apple askpass integrado)
#   2. Instalación de Homebrew (x86_64) con asistente gráfico integrado
#   3. Wi-Fi Intel (Instalación y configuración de HeliPort + renombrado de red)
#   4. Remapeo de teclado Windows (Invierte Ctrl y Super/Windows para atajos tipo PC)
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------------------
# 1. Asistente Gráfico de Sudo Integrado (Askpass)
# ------------------------------------------------------------------------------
askpass_prompt() {
    PROMPT_MSG="${1:-Se requieren permisos de administrador en tu Hackintosh:}"
    osascript -e 'tell application "System Events"
activate
text returned of (display dialog "'"$PROMPT_MSG"'\n\nIngresa tu contraseña:" default answer "" with hidden answer with icon caution with title "Autenticación del Sistema")
end tell'
}

# Si el script es invocado por sudo o con la opción --askpass, actuar como askpass
if [ "$1" = "--askpass" ] || [[ "$1" == *assword* ]] || [[ "$1" == *ontraseña* ]]; then
    askpass_prompt "$1"
    exit 0
fi

export SUDO_ASKPASS="$DIR/setup.sh"

# ------------------------------------------------------------------------------
# 2. Instalación de Homebrew (x86_64)
# ------------------------------------------------------------------------------
setup_brew() {
    echo ""
    echo "================================================================="
    echo " Instalando Homebrew para macOS Sequoia (x86_64)..."
    echo "================================================================="
    export SUDO_ASKPASS="$DIR/setup.sh"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/df3c2556141c012eaba0453ede7a1bd4f05b824c/install.sh)"
}

# ------------------------------------------------------------------------------
# 3. Configuración de Wi-Fi Intel (HeliPort.app)
# ------------------------------------------------------------------------------
setup_wifi() {
    echo ""
    echo "================================================================="
    echo " [1/2] Configurando Wi-Fi Intel (itlwm + HeliPort)..."
    echo "================================================================="

    if [ -d "/Applications/HeliPort.app" ]; then
        echo "[✓] HeliPort.app ya se encuentra instalado en /Applications."
    else
        echo "[*] Descargando última versión de HeliPort desde GitHub..."
        DMG_URL=$(curl -s "https://api.github.com/repos/OpenIntelWireless/HeliPort/releases/latest" \
            | grep "browser_download_url.*HeliPort.dmg" \
            | head -n 1 \
            | cut -d '"' -f 4)

        if [ -z "$DMG_URL" ]; then
            DMG_URL="https://github.com/OpenIntelWireless/HeliPort/releases/download/v1.5.0/HeliPort.dmg"
        fi

        TEMP_DMG="/tmp/HeliPort.dmg"
        curl -fsSL -o "$TEMP_DMG" "$DMG_URL"

        echo "[*] Montando imagen y copiando HeliPort.app..."
        yes Y | hdiutil attach "$TEMP_DMG" -nobrowse -quiet 2>/dev/null || true

        if [ -d "/Volumes/HeliPort/HeliPort.app" ]; then
            cp -R /Volumes/HeliPort/HeliPort.app /Applications/
            xattr -cr /Applications/HeliPort.app
            hdiutil detach /Volumes/HeliPort -quiet 2>/dev/null || true
            rm -f "$TEMP_DMG"
            echo "[✓] HeliPort.app instalado correctamente en /Applications."
        else
            echo "[!] Error al montar la imagen de HeliPort."
            exit 1
        fi
    fi

    # Iniciar HeliPort si no está en ejecución
    if ! pgrep -x "HeliPort" > /dev/null; then
        echo "[*] Iniciando HeliPort.app..."
        open /Applications/HeliPort.app
    fi

    # Asegurar arranque automático al iniciar sesión
    echo "[*] Configurando HeliPort en el inicio de sesión automático..."
    osascript -e '
    tell application "System Events"
        if not (exists login item "HeliPort") then
            make login item at end with properties {path:"/Applications/HeliPort.app", hidden:false, name:"HeliPort"}
        end if
    end tell' 2>/dev/null || true

    # Renombrar interfaz en1 a "Wi-Fi (Intel)" si aún se llama Ethernet Adapter
    if networksetup -listallnetworkservices 2>/dev/null | grep -q "Ethernet Adapter (en1)"; then
        echo "[*] Renombrando servicio de red a 'Wi-Fi (Intel)'..."
        networksetup -renamenetworkservice "Ethernet Adapter (en1)" "Wi-Fi (Intel)" 2>/dev/null || true
    fi

    echo "[✓] Wi-Fi Intel configurado y activo en la barra de menús."
}

# ------------------------------------------------------------------------------
# 4. Remapeo de Teclado Windows (Ctrl <-> Super / Windows)
# ------------------------------------------------------------------------------
setup_keyboard_mapping() {
    echo ""
    echo "================================================================="
    echo " [2/2] Aplicando parche de teclado Windows (Inversión Ctrl <-> Super)..."
    echo "================================================================="

    # Aplicar inmediatamente en la sesión activa con hidutil:
    # 0x7000000E0 (Left Control)  <-> 0x7000000E3 (Left GUI / Super)
    # 0x7000000E4 (Right Control) <-> 0x7000000E7 (Right GUI / Super)
    hidutil property --set '{"UserKeyMapping":[
        {"HIDKeyboardModifierMappingSrc":30064771296,"HIDKeyboardModifierMappingDst":30064771299},
        {"HIDKeyboardModifierMappingSrc":30064771299,"HIDKeyboardModifierMappingDst":30064771296},
        {"HIDKeyboardModifierMappingSrc":30064771300,"HIDKeyboardModifierMappingDst":30064771303},
        {"HIDKeyboardModifierMappingSrc":30064771303,"HIDKeyboardModifierMappingDst":30064771300}
    ]}' > /dev/null

    # Crear LaunchAgent persistente para cada inicio de sesión
    LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
    LAUNCH_AGENT_FILE="$LAUNCH_AGENT_DIR/com.hackintosh.keymapping.plist"

    mkdir -p "$LAUNCH_AGENT_DIR"
    cat << 'EOF' > "$LAUNCH_AGENT_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hackintosh.keymapping</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":30064771296,"HIDKeyboardModifierMappingDst":30064771299},{"HIDKeyboardModifierMappingSrc":30064771299,"HIDKeyboardModifierMappingDst":30064771296},{"HIDKeyboardModifierMappingSrc":30064771300,"HIDKeyboardModifierMappingDst":30064771303},{"HIDKeyboardModifierMappingSrc":30064771303,"HIDKeyboardModifierMappingDst":30064771300}]}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

    launchctl unload "$LAUNCH_AGENT_FILE" 2>/dev/null || true
    launchctl load "$LAUNCH_AGENT_FILE" 2>/dev/null || true

    echo "[✓] Teclado remapeado con éxito:"
    echo "    - La tecla física Ctrl ahora ejecuta los comandos de Command (Copiar, Pegar, Guardar, etc.)."
    echo "    - La tecla física Super/Windows ahora actúa como Control."
    echo "    - Configurado para persistir automáticamente en cada reinicio."
}

# Opción para restaurar teclado por defecto
revert_keyboard_mapping() {
    echo "[*] Restaurando mapeo de teclado original de macOS..."
    hidutil property --set '{"UserKeyMapping":[]}' > /dev/null
    rm -f "$HOME/Library/LaunchAgents/com.hackintosh.keymapping.plist"
    echo "[✓] Teclas restauradas a sus valores por defecto de macOS."
}

# ------------------------------------------------------------------------------
# Flujo Principal
# ------------------------------------------------------------------------------
case "$1" in
    --revert-keyboard)
        revert_keyboard_mapping
        exit 0
        ;;
    --keyboard-only)
        setup_keyboard_mapping
        exit 0
        ;;
    --wifi-only)
        setup_wifi
        exit 0
        ;;
    --brew)
        setup_brew
        exit 0
        ;;
    *)
        setup_wifi
        setup_keyboard_mapping
        echo ""
        echo "================================================================="
        echo " ¡Configuración post-instalación completada con éxito!"
        echo "================================================================="
        echo "  - Wi-Fi disponible en el icono de HeliPort en la barra superior."
        echo "  - Atajos de teclado Windows activados (Ctrl+C, Ctrl+V, etc.)."
        echo "  - Asistente gráfico de elevación (askpass) listo."
        echo "================================================================="
        ;;
esac
