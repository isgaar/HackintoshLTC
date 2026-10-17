#!/bin/bash
# Asistente gráfico (AppleScript askpass) para la elevación de permisos durante la instalación de Homebrew en Hackintosh (macOS x86_64).
# Uso:
#   SUDO_ASKPASS="./apple_askpass.sh" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/df3c2556141c012eaba0453ede7a1bd4f05b824c/install.sh)"

osascript -e 'tell application "System Events"
activate
text returned of (display dialog "Homebrew necesita permisos de administrador para configurar /usr/local en tu Hackintosh:\n\nIngresa tu contraseña:" default answer "" with hidden answer with icon caution with title "Instalador de Homebrew")
end tell'
