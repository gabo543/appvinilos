#!/usr/bin/env bash
set -euo pipefail

# Regenera las carpetas de plataforma (android/ios/web/windows/macos/linux) si no existen.
# Útil si el proyecto fue exportado sin esas carpetas.

cd "$(dirname "$0")"

if [ ! -f "pubspec.yaml" ]; then
  echo "No encuentro pubspec.yaml en $(pwd). Ejecuta este script dentro de la raíz del proyecto."
  exit 1
fi

echo ">> Flutter doctor (opcional):"
flutter doctor || true

echo ">> Ejecutando: flutter create ."
# Esto NO debería sobreescribir tu carpeta lib/ ni assets; solo crea/actualiza los runners de plataforma.
flutter create .

echo ">> Instalando dependencias:"
flutter pub get

echo "Listo. Ahora puedes compilar:"
echo "  flutter build apk --release"
