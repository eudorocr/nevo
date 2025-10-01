# Flutter APK CI con ícono personalizado

Este repositorio compila un APK con GitHub Actions **y** genera el **ícono de la app** automáticamente usando `flutter_launcher_icons`.

## Pasos
1. Crea un repo en GitHub y sube todo el contenido de este ZIP.
2. Ve a **Actions** → “Build Android APK”.
3. Al finalizar, descarga el APK desde **Artifacts** o el **Release `latest`**.

## ¿Qué hace el workflow?
- Genera un proyecto Flutter base (`flutter create app`).
- Inyecta tu `main.dart` desde `ci/app_main.dart`.
- Copia el ícono (`ci/app_icon.png`) y la config (`ci/flutter_launcher_icons.yaml`).
- Añade dependencias (`shared_preferences` y `flutter_launcher_icons` [dev]).
- Ejecuta `flutter_launcher_icons` para generar los mipmaps.
- Compila el APK y lo publica.
