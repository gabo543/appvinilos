# Regenera las carpetas de plataforma (android/ios/web/windows/macos/linux) si no existen.
# Ejecuta este script en PowerShell desde la raíz del proyecto.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (!(Test-Path ".\pubspec.yaml")) {
  Write-Host "No encuentro pubspec.yaml en $PWD. Ejecuta este script dentro de la raíz del proyecto."
  exit 1
}

Write-Host ">> Flutter doctor (opcional):"
flutter doctor

Write-Host ">> Ejecutando: flutter create ."
flutter create .

Write-Host ">> Instalando dependencias:"
flutter pub get

Write-Host "Listo. Ahora puedes compilar:"
Write-Host "  flutter build apk --release"
