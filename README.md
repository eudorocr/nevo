# Flutter APK CI — Zero‑install (GitHub Actions)

Este repositorio construye **un APK de Android** usando **GitHub Actions**, sin instalar nada en tu PC.

## 🚀 Pasos rápidos

1. **Crea un repositorio nuevo en GitHub** (público o privado).
2. **Sube todos los archivos de este ZIP** tal cual a la raíz del repo.
3. En GitHub, ve a **Actions** → se disparará el workflow **Build Android APK** automáticamente.
4. Al finalizar, tendrás dos formas de descargar el APK:
   - **Artifacts** del run en Actions (botón *Download artifact*).
   - **Release `latest`** del repo (se crea/actualiza automáticamente).

> Tu `main.dart` ya está incluido aquí en `ci/app_main.dart`. El workflow generará un proyecto Flutter base y copiará tu `main.dart` al lugar correcto antes de compilar.

---

## 📁 Estructura de este repo

```
.
├─ .github/workflows/android-apk.yml   # Workflow de CI para compilar y publicar APK
├─ ci/app_main.dart                    # Tu main.dart
└─ web-download/index.html             # Página web simple para descargar el APK del Release 'latest'
```

> La carpeta `web-download/` es opcional. La puedes publicar con GitHub Pages, Netlify o Vercel para tener un botón de descarga público.

---

## 🧪 ¿Cómo funciona el workflow?

1. Instala Java y Flutter estable.
2. Ejecuta `flutter create app` para generar un proyecto nuevo en `./app`.
3. Reemplaza `app/lib/main.dart` con `ci/app_main.dart` (tu app).
4. Corre `flutter pub get` y construye `flutter build apk --release`.
5. Publica `app/build/app/outputs/flutter-apk/app-release.apk` como:
   - **Artifact** del run de Actions.
   - **Activo de un Release** del repo con tag `latest` (lo crea si no existe).

> Si quieres firmar el APK para distribución, puedes agregar variables/secretos y pasos de firma más adelante.

---

## 🔐 Permisos y Secrets (opcional)

- Para subir al Release, el workflow usa el `GITHUB_TOKEN` que GitHub provee automáticamente.
- Si el repo es **privado**, los Releases serán privados y solo accesibles para colaboradores con permisos.

---

## 🌐 Página de descarga (web-download/)

- Publica la carpeta `web-download/` (por ejemplo con **GitHub Pages** desde otra rama o con Netlify).
- Edita la constante `OWNER` y `REPO` en `web-download/index.html` para apuntar a tu repo.
- La página leerá el Release `latest` y mostrará un botón **Descargar APK**.

---

## ❓ Problemas comunes

- **Error en Gradle/Android SDK**: el workflow usa imágenes limpias y versiones estables; repetir el run suele resolver descargas intermitentes.
- **APK no aparece en Releases**: valida que el job no haya fallado en el paso "Create/Update Release".
- **Mi app requiere permisos especiales / minSdk / nombre**: agrega un paso extra en el workflow para editar `app/android/app/build.gradle` o `AndroidManifest.xml` antes de compilar.

¡Éxitos! 💪📱