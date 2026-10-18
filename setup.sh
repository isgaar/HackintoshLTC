#!/bin/bash
# ==============================================================================
# Script: setup.sh (HackintoshLTC Post-Install Setup)
# Descripción: Automatiza la configuración esencial post-instalación:
#   1. Asistente gráfico de elevación (Apple askpass integrado)
#   2. Instalación de Homebrew (x86_64) con asistente gráfico integrado
#   3. Wi-Fi Intel (Instalación y configuración de HeliPort + renombrado de red)
#   4. Remapeo de teclado Windows (Invierte Ctrl y Super/Windows para atajos tipo PC)
#   5. Autocompletado y autocorrección de rutas con minúsculas hacia mayúsculas
#   6. Registro del comando CLI 'antigravity-ide' ('antigravity-ide .')
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
    echo " [1/4] Configurando Wi-Fi Intel (itlwm + HeliPort)..."
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
    echo " [2/4] Aplicando parche de teclado Windows (Inversión Ctrl <-> Super)..."
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
# 5. Soporte Insensible a Mayúsculas/Minúsculas en Terminal (zsh, bash, inputrc)
# ------------------------------------------------------------------------------
setup_terminal_case_insensitive() {
    echo ""
    echo "================================================================="
    echo " [3/4] Configurando autocompletado y rutas insensibles a mayúsculas..."
    echo "================================================================="

    # 1. Configuración de zsh (~/.zshrc) - Shell predeterminado de macOS
    ZSHRC="$HOME/.zshrc"
    touch "$ZSHRC"

    if ! grep -q "Hackintosh Terminal Case-Insensitive" "$ZSHRC"; then
        echo "[*] Añadiendo autocompletado y autocorrección de mayúsculas a ~/.zshrc..."
        cat << 'EOF' >> "$ZSHRC"

# >>> Hackintosh Terminal Case-Insensitive Setup >>>
# Autocompletado insensible a mayúsculas/minúsculas (ej: doc<TAB> completa a Documents/)
autoload -Uz compinit && compinit -C
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
setopt nocaseglob

# Resolver automáticamente directorios con su formato canónico de mayúsculas (ej: cd documents -> Documents)
setopt CHASE_LINKS
# <<< Hackintosh Terminal Case-Insensitive Setup <<<
EOF
        echo "[✓] Configuración añadida a ~/.zshrc."
    else
        echo "[✓] ~/.zshrc ya cuenta con la configuración insensible a mayúsculas."
    fi

    # 2. Configuración de Readline (~/.inputrc) para herramientas interactivas
    INPUTRC="$HOME/.inputrc"
    touch "$INPUTRC"

    if ! grep -q "completion-ignore-case" "$INPUTRC"; then
        echo "[*] Configurando insensibilidad a mayúsculas en ~/.inputrc..."
        cat << 'EOF' >> "$INPUTRC"

# Coincidencia insensible a mayúsculas en autocompletado de Readline (bash, python, etc.)
set completion-ignore-case on
set show-all-if-ambiguous on
EOF
        echo "[✓] Configuración añadida a ~/.inputrc."
    else
        echo "[✓] ~/.inputrc ya cuenta con 'completion-ignore-case on'."
    fi

    # 3. Configuración para bash (~/.bashrc) por compatibilidad
    BASHRC="$HOME/.bashrc"
    touch "$BASHRC"

    if ! grep -q "Hackintosh Bash Case-Insensitive" "$BASHRC"; then
        echo "[*] Configurando compatibilidad en ~/.bashrc..."
        cat << 'EOF' >> "$BASHRC"

# >>> Hackintosh Bash Case-Insensitive Setup >>>
shopt -s nocaseglob 2>/dev/null
shopt -s nocasematch 2>/dev/null
shopt -s cdspell 2>/dev/null
# <<< Hackintosh Bash Case-Insensitive Setup <<<
EOF
        echo "[✓] Configuración añadida a ~/.bashrc."
    fi

    echo "[✓] Terminal configurada: escribir directorios en minúsculas coincidirá y resolverá automáticamente a mayúsculas."
}

# ------------------------------------------------------------------------------
# 6. Registro del comando CLI 'antigravity-ide' en la Terminal
# ------------------------------------------------------------------------------
setup_antigravity_cli() {
    echo ""
    echo "================================================================="
    echo " [4/4] Registrando comando 'antigravity-ide' en la Terminal..."
    echo "================================================================="

    APP_PATH="/Applications/Antigravity IDE.app"
    if [ ! -d "$APP_PATH" ]; then
        APP_PATH=$(find /Applications "$HOME/Applications" -maxdepth 2 -name "Antigravity IDE.app" 2>/dev/null | head -n 1)
    fi

    if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
        echo "[!] Advertencia: No se encontró 'Antigravity IDE.app' instalada en /Applications."
        echo "    El comando se configurará asumiendo la ruta estándar: /Applications/Antigravity IDE.app"
        APP_PATH="/Applications/Antigravity IDE.app"
    fi

    TARGET_BIN="/usr/local/bin/antigravity-ide"
    LOCAL_BIN="$HOME/.local/bin/antigravity-ide"

    mkdir -p "/usr/local/bin" "$HOME/.local/bin"

    # Script wrapper inteligente para antigravity-ide:
    # 1. Soporta 'antigravity-ide .' para abrir el directorio actual
    # 2. Soporta 'antigravity-ide <carpeta>' resolviendo automáticamente minúsculas a mayúsculas canónicas
    # 3. Soporta flags (-v, --help, etc.) pasándolos transparentemente al binario
    TMP_WRAPPER="/tmp/antigravity-ide-launcher"
    cat << 'EOF' > "$TMP_WRAPPER"
#!/usr/bin/env bash
# Wrapper CLI para Antigravity IDE
# Soporta 'antigravity-ide .' y resolución automática de rutas en minúsculas hacia mayúsculas

APP_BIN="/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide"

if [ ! -f "$APP_BIN" ]; then
    FOUND_APP=$(find /Applications "$HOME/Applications" -maxdepth 2 -name "Antigravity IDE.app" 2>/dev/null | head -n 1)
    if [ -n "$FOUND_APP" ] && [ -f "$FOUND_APP/Contents/Resources/app/bin/antigravity-ide" ]; then
        APP_BIN="$FOUND_APP/Contents/Resources/app/bin/antigravity-ide"
    else
        echo "Error: No se encontró el binario de Antigravity IDE en $APP_BIN" >&2
        exit 1
    fi
fi

if [ $# -eq 0 ]; then
    exec "$APP_BIN"
fi

ARGS=()
for arg in "$@"; do
    if [[ "$arg" == -* ]]; then
        ARGS+=("$arg")
    elif [ -d "$arg" ]; then
        # Resolver directorio canónico con mayúsculas reales
        REAL_DIR=$(/bin/zsh -c 'setopt CHASE_LINKS; cd "$1" 2>/dev/null && pwd' dummy "$arg" 2>/dev/null)
        if [ -n "$REAL_DIR" ]; then
            ARGS+=("$REAL_DIR")
        else
            ARGS+=("$arg")
        fi
    elif [ -e "$arg" ]; then
        DIR_PART=$(dirname "$arg")
        BASE_PART=$(basename "$arg")
        REAL_DIR=$(/bin/zsh -c 'setopt CHASE_LINKS; cd "$1" 2>/dev/null && pwd' dummy "$DIR_PART" 2>/dev/null)
        if [ -n "$REAL_DIR" ]; then
            ARGS+=("$REAL_DIR/$BASE_PART")
        else
            ARGS+=("$arg")
        fi
    else
        ARGS+=("$arg")
    fi
done

exec "$APP_BIN" "${ARGS[@]}"
EOF

    chmod +x "$TMP_WRAPPER"

    # Intentar instalar en /usr/local/bin (disponible globalmente en el sistema)
    if [ -w "/usr/local/bin" ]; then
        cp "$TMP_WRAPPER" "$TARGET_BIN"
        chmod +x "$TARGET_BIN"
    else
        sudo cp "$TMP_WRAPPER" "$TARGET_BIN" 2>/dev/null || true
        sudo chmod +x "$TARGET_BIN" 2>/dev/null || true
    fi

    # Copiar también en ~/.local/bin por redundancia
    cp "$TMP_WRAPPER" "$LOCAL_BIN"
    chmod +x "$LOCAL_BIN"
    rm -f "$TMP_WRAPPER"

    echo "[✓] Comando 'antigravity-ide' registrado correctamente en el sistema:"
    echo "    - Ubicación: $TARGET_BIN"
    echo "    - Uso:"
    echo "        antigravity-ide .            # Abre el directorio actual"
    echo "        antigravity-ide <carpeta>    # Abre la carpeta indicada (auto-resuelve minúsculas a mayúsculas)"
    echo "        antigravity-ide              # Abre la aplicación"
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
    --terminal-only)
        setup_terminal_case_insensitive
        exit 0
        ;;
    --ide-only|--antigravity-only)
        setup_antigravity_cli
        exit 0
        ;;
    *)
        setup_wifi
        setup_keyboard_mapping
        setup_terminal_case_insensitive
        setup_antigravity_cli
        echo ""
        echo "================================================================="
        echo " ¡Configuración post-instalación completada con éxito!"
        echo "================================================================="
        echo "  - Wi-Fi disponible en el icono de HeliPort en la barra superior."
        echo "  - Atajos de teclado Windows activados (Ctrl+C, Ctrl+V, etc.)."
        echo "  - Terminal inteligente: rutas en minúsculas resuelven a mayúsculas."
        echo "  - Comando 'antigravity-ide .' registrado y listo para usar."
        echo "  - Asistente gráfico de elevación (askpass) listo."
        echo "================================================================="
        ;;
esac
