# gaboLP
## Nota importante (APK / Android)
Este ZIP contiene el código (`lib/`, `assets/`, etc.). Si tu copia del proyecto **no tiene** carpeta `android/`,
Flutter no puede compilar APK (fallará en `assembleRelease`).

Solución rápida:
- macOS / Linux: `./regen_platforms.sh`
- Windows (PowerShell): `./regen_platforms.ps1`

Eso ejecuta `flutter create .` en la raíz del proyecto y vuelve a generar `android/` (y otras plataformas) sin tocar tu `lib/`.
