# Plan de implementación — AppScanner (Flutter · Android)

Documento de traspaso. Describe el estado actual del proyecto y las fases pendientes con especificaciones suficientes para implementarlas sin contexto adicional.

## 1. Resumen

App Android en Flutter para escanear documentos con la cámara:

captura con guía → recorte con corrección de perspectiva → filtros → OCR on-device → PDF multipágina compartible.

Todo el procesamiento ocurre en el dispositivo; no hay backend ni servicios de pago.

## 2. Estado actual

| Fase | Descripción | Estado |
|------|-------------|--------|
| Captura | Cámara con marco guía, flash, miniatura, guardado por sesión | Completada |
| Recorte | Detección de bordes + esquinas arrastrables + corrección de perspectiva | Completada |
| Filtros | Original, Mejorar, Grises, B y N, Aclarar, Invertir, Sin sombra | Completada |
| OCR | ML Kit on-device (script latino: español/inglés), texto copiable | Completada |
| Páginas | Lista de páginas de la sesión con visor | Completada |
| PDF | PDF multipágina, reordenar y compartir | Completada (F6) — pendiente probar en dispositivo |
| Pulido | Ícono, splash, persistencia, estados vacíos, v1.0.0 | Completada (F7) — pendiente probar en dispositivo |

## 3. Entorno de desarrollo (Windows)

- Flutter 3.47.7 (Dart 3.13.5) — (en el `PATH`)
- Android SDK 36 — `%LOCALAPPDATA%\Android\Sdk` (platform-tools, platform 36, build-tools 36)
- JDK 21 — (`JAVA_HOME`)
- Android Studio 2026 instalado solo como IDE/emulador opcional.

Comandos:

```bash
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

**Importante:** compilar siempre con `--target-platform android-arm64` en desarrollo. Sin ese flag Flutter compila 4 arquitecturas y las librerías nativas de OpenCV hacen que el build tarde 45+ minutos; con el flag tarda ~1-2 min (incremental).

Notas:
- `flutter doctor` puede reportar licencias de paquetes no usados (TV, autos, AR) y falta de Visual Studio. Ninguno bloquea el build Android.
- `flutter test` NO corre en este equipo: el hook de native assets de `opencv_dart` intenta compilar OpenCV para Windows y falla por falta de compilador C++ (`CMAKE_CXX_COMPILER not set`). Para correr los tests hay que instalar Visual Studio Build Tools (carga "Desarrollo de escritorio con C++") o ejecutarlos en un dispositivo con `flutter test -d <id>`. Mientras tanto, `flutter analyze` + build son la verificación.
- Ícono y splash se regeneran con `dart run flutter_launcher_icons` y `dart run flutter_native_splash:create` (configuración al final de `pubspec.yaml`; fuente en `assets/icon/`, se redibuja con `python assets/icon/make_icon.py`).
- Para probar en dispositivo físico: depuración USB activada; `adb devices` debe listar el teléfono.

## 4. Arquitectura del código (`lib/`)

- `main.dart` — `EscanerApp`: MaterialApp, tema Material 3 (seed teal), home.
- `models/scan_session.dart` — `ScanSession(dirPath, pages)` y `ScanPage(originalPath, currentPath)`; `stamp`, `createdAt` (parseado del nombre de carpeta) y `title` ("Escaneo 17 oct 2026, 14:05").
- `services/`
  - `document_detector.dart` — detección y warp:
    - redimensiona a 800 px de ancho, gris, gaussian blur 5×5, Canny 60/180, cierre morfológico 5×5, contornos externos, elige el mayor cuadrilátero con área > 15 % y lo ordena (tl, tr, br, bl); fallback: marco con inset del 3 %.
    - `applyWarp` calcula tamaño destino por promedio de lados y aplica transformación de perspectiva.
  - `image_filters.dart` — enum `ScanFilter` y aplicación de cada filtro con OpenCV:
    - `enhance`: CLAHE (clipLimit 3, tiles 8×8) sobre el canal L de LAB.
    - `bw`: umbral adaptativo gaussiano (block 25, C 12).
    - `lighten`: `convertScaleAbs` (alpha 1.15, beta 18).
    - `invert`: `bitwiseNOT`. `noShadow`: divide gris entre blur 41×41 (escala 200).
  - `ocr_service.dart` — `TextRecognizer` (script latin) sobre la ruta de imagen.
  - `pdf_service.dart` — `PdfService.buildPdf(pages)`: PDF A4 (margen 16 pt, imagen `contain`) con una página por `currentPath`; si existe `*_ocr.txt` superpone el texto en `pw.Opacity(0)` (seleccionable); sanitiza a Latin-1 (Helvetica) y si aun así falla, reconstruye sin capa de texto. Guarda `Escaneo_yyyyMMdd_HHmm.pdf` en `getTemporaryDirectory()`.
  - `import_service.dart` — importación: `importImage` re-encodea con OpenCV (`imread` aplica la orientación EXIF) a `page_N.jpg`; `openPdf`/`renderPdfPages` renderizan cada página del PDF con `pdfx` a JPEG (lado mayor 2000 px, fondo blanco, calidad 90).
  - `page_editor.dart` — `PageEditor.rotateClockwise(page)`: `cv.rotate` sobre el archivo actual y escribe `<base>_r<ángulo>.jpg` (ángulo acumulado 90/180/270/0; el sufijo previo se reemplaza). El original no se toca.
  - `session_store.dart` — `SessionStore.save/loadAll/delete`: `session.json` por sesión (nombres de archivo relativos, escritura atómica vía `.tmp` + rename, guardados en cola). `loadAll` lista `scans/*` de más nueva a más vieja; sin `session.json` reconstruye desde `page_N.jpg` eligiendo el mejor derivado (`_crop_<filtro>` más reciente > `_crop` > original).
- `screens/`
  - `home_screen.dart` — encabezado + "Nuevo escaneo" y sección "Escaneos anteriores" (miniatura, fecha, N páginas; tap abre `PagesScreen`; menú/long-press "Eliminar" con confirmación). Estado vacío, loading y snackbar de error.
  - `camera_screen.dart` — `CameraController` (cámara trasera, `ResolutionPreset.max`, sin audio), preview cover, guía `DocumentGuidePainter`, flash torch, disparo, miniaturas, sesión.
  - `crop_screen.dart` — imagen + 4 esquinas arrastrables (radio de imán 56 px), rejilla de tercios, "Reiniciar", "Recortar".
  - `filter_screen.dart` — chips horizontales, preview cacheado (máx. 1400 px), "Guardar página" (filtro a resolución completa).
  - `pages_screen.dart` — `ReorderableListView.builder` (handle de arrastre, `onReorderItem` mueve en `session.pages` y guarda la sesión), miniaturas con `cacheWidth`, estado vacío y botón inferior "Crear PDF" (deshabilitado sin páginas, spinner mientras genera, `Printing.sharePdf`, snackbar en error).
  - `photo_viewer_screen.dart` — visor con zoom (InteractiveViewer) + "Extraer texto".
  - `ocr_screen.dart` — texto reconocido, seleccionable, copiar, guarda `*_ocr.txt`.
- `widgets/document_guide_painter.dart` — marco guía (A4) con esquinas verdes y zona oscurecida.

Convenciones:
- Sin comentarios en el código; `flutter_lints` activo; textos de UI en español.
- Los derivados de una página (recorte/filtro) se calculan siempre desde el archivo original de su paso; nunca encadenar recorte sobre recorte.

## 5. Flujo de navegación (resultados por `pop`)

```
Home
 ├─ (escaneo anterior) ─ PagesScreen (misma rama que abajo)
 └─ CameraScreen            pop<int>  = número de páginas de la sesión
     ├─ (captura) ── CropScreen        pop<String> = ruta recortada | null = cancelar
     │               └─ FilterScreen(source: recorte)
     │                                    pop<String> = ruta final | null = usar recorte
     └─ (miniatura) ─ PagesScreen
                       └─ PhotoViewerScreen
                           └─ OcrScreen
```

La cámara acumula `ScanPage` en la `ScanSession` en memoria al aceptar una página y persiste `session.json` (sin bloquear el flujo). Home recarga la lista al volver de la cámara o de `PagesScreen`.

## 6. Almacenamiento

`getApplicationDocumentsDirectory()/scans/<sessionStamp>/`

- `page_N.jpg` — original capturado.
- `page_N_crop.jpg` — recorte con perspectiva.
- `page_N_crop_<filtro>.jpg` — versión con filtro (p. ej. `page_1_crop_bw.jpg`).
- `preview_page_N_crop_<filtro>.jpg` — caché de previews a 1400 px.
- `page_N_crop_<filtro>_ocr.txt` — texto reconocido de la página.
- `page_N_crop_<filtro>_r90.jpg` (o `_r180`, `_r270`, `_r0`) — rotación acumulada sobre la versión actual.
- `<imagen actual>_ocr.json` — palabras del OCR con sus cajas en píxeles de la imagen: `{"width":W,"height":H,"words":[{"text":"…","l":x1,"t":y1,"r":x2,"b":y2}]}`. Rotar o anotar borra `_ocr.txt` y `_ocr.json` (ya no corresponden).
- `session.json` — orden y estado de las páginas: `{"title":"Contrato renta","pages":[{"original":"page_1.jpg","current":"page_1_crop_bw.jpg"}, …]}`. `title` solo existe si el usuario renombró; sin él se usa el título por fecha.
- Páginas importadas de PDF: `original == current == page_N.jpg` (sin recorte).

El PDF generado va a `getTemporaryDirectory()` (no a la carpeta de la sesión).

## 7. F6 — PDF multipágina, reordenar y compartir (IMPLEMENTADA, sin probar en dispositivo)

- [x] 7.1 Dependencias: `pdf ^3.13.1` y `printing ^5.15.1` (sin cambios en Manifest ni Gradle).
- [x] 7.2 Reordenar en `PagesScreen` con `ReorderableListView.builder` (`onReorderItem`, ya que `onReorder` está deprecado en Flutter 3.47); el orden de `session.pages` es el del PDF y se persiste.
- [x] 7.3 "Crear PDF": A4, una página por `currentPath`, capa de texto OCR invisible/seleccionable cuando existe `*_ocr.txt`, nombre `Escaneo_yyyyMMdd_HHmm.pdf`, compartir con `Printing.sharePdf`.
- [x] 7.4 Sin páginas → botón deshabilitado y estado vacío; error → snackbar "No se pudo crear el PDF.".
- [ ] Criterios de aceptación en dispositivo: abre en visor externo, conserva el orden tras reordenar, todas las páginas presentes, texto seleccionable donde hubo OCR, orientación EXIF correcta.

Decisiones:
- La capa de texto no está alineada palabra por palabra con la imagen (es un bloque de 6 pt sobre el área de la imagen); suficiente para seleccionar/buscar, no para "resaltar en su sitio".
- Helvetica solo cubre Latin-1: comillas tipográficas, guiones largos y viñetas se normalizan a ASCII y lo demás fuera de rango se vuelve `?`. Si el render falla de todas formas, se reconstruye el PDF completo sin capa de texto.
- La generación corre en el hilo principal y carga todos los JPEG en memoria; revisar tiempos con >30 páginas (posible mejora: `compute`/isolate).

## 8. F7 — Pulido (IMPLEMENTADA, sin probar en dispositivo)

- [x] Ícono adaptativo (fondo #00796B, hoja blanca con línea de escaneo) y splash (incluye Android 12+) generados con `flutter_launcher_icons` y `flutter_native_splash`.
- [x] Nombre visible: "AppScanner" (2026-10-17). El `applicationId` sigue siendo `com.pedro.escaner` y el paquete Dart `escaner`; cambiarlos crearía otra app distinta en el teléfono.
- [x] Persistencia de sesiones entre arranques: `SessionStore` + `session.json`; carpetas antiguas sin manifiesto se reconstruyen desde los archivos.
- [x] Estados vacíos y mensajes de error en Home y Páginas; miniaturas con `cacheWidth` para reducir memoria.
- [x] Versión 1.0.0+1 en `pubspec.yaml`.
- [ ] Checklist de publicación (firma release, `flutter build appbundle`, política de privacidad) si se decide publicar.

## 9. Checklist de pruebas en dispositivo

Última sesión de pruebas: 2026-10-17, un Samsung con Android 16, APK debug arm64 vía `adb`.

- [x] Permiso de cámara (primer uso): el diálogo del sistema aparece y al aceptar la cámara arranca.
- [x] Reanudación al volver de segundo plano (home → reabrir: la cámara vuelve sola). **Bug encontrado y corregido el 2026-10-17:** `didChangeAppLifecycleState` destruía el controlador en `inactive` pero en `resumed` salía temprano (controlador nulo) y nunca lo recreaba → spinner infinito; pasaba también al abrir la hoja de compartir del PDF o un diálogo. Ahora `inactive`/`paused` liberan la cámara y `resumed` la reinicializa (con guarda `_initializing`).
- [x] Captura con guía visible; linterna alterna (ícono cambia y la escena se ilumina).
- [x] Recorte: detección automática; resultado enderezado y legible. [ ] Arrastrar esquinas (no probado).
- [x] Filtros: "B y N" aplica preview y guarda en alta resolución (`page_1_crop_bw.jpg`, 0.9 MB); "Original" guarda `page_N_crop.jpg`. [ ] Los otros 5 chips (no probados).
- [x] OCR: extrae texto legible de la página B/N, "Copiar todo" muestra "Texto copiado al portapapeles.", se crea `page_1_crop_bw_ocr.txt` (2.3 KB).
- [x] F6: la lista muestra "Página N" con miniatura, handle de arrastre y botón "Crear PDF" habilitado con 3 páginas.
- [x] F6: arrastrar el handle reordena y renumera; `session.json` pasa a `[page_3, page_1, page_2]`.
- [x] F6: "Crear PDF" abre la hoja de compartir con `Escaneo_yyyyMMdd_HHmm.pdf`. Inspeccionado en PC con pypdf: 3 páginas A4 (595×842 pt), una imagen JPEG por página en el orden reordenado, y solo la página con OCR tiene texto extraíble (2330 caracteres). [ ] Abrirlo en Drive/Adobe y seleccionar texto a mano (no probado).
- [ ] F6: sesión sin páginas → botón deshabilitado y estado vacío. No se puede llegar por la UI (PagesScreen solo se abre con ≥1 página); verificado solo por código.
- [x] F7: splash teal con la hoja al abrir (Android 16) e ícono adaptativo nuevo en el launcher. [ ] Modo oscuro (no revisado).
- [x] F7: `session.json` se escribe al guardar cada página con el orden y el derivado correcto.
- [x] F7: Home sin escaneos muestra "Tus escaneos guardados aparecerán aquí.".
- [x] F7: cerrar la app por completo y reabrir → "Escaneo 17 oct 2026, 17:00 · 3 páginas" con miniatura; tocar abre sus páginas.
- [x] F7: eliminar (long-press) muestra "¿Eliminar este escaneo? Se borrarán sus 3 páginas."; al confirmar desaparece de la lista y la carpeta `scans/<stamp>` se borra.
- [ ] F7: con 30+ páginas, la lista de páginas y Home van fluidas y "Crear PDF" termina sin cerrar la app.
- [ ] Casos borde: sin cámara, permiso denegado, foto muy oscura (sin detección).


## 10. Bloques 1 y 2 — Captura, importación y edición (plan del 2026-10-17)

Dispositivo de pruebas: Samsung Galaxy S10+ SM-G975U1 (Android 12), vía `adb -s <serial>`. Cada punto se prueba en el teléfono antes de pasar al siguiente.

### Parte 1 — 1.1 galería, 1.2 PDF, 2.1 rotar, renombrar (HECHA Y PROBADA)

- [x] 1.1 Importar fotos: el botón de galería abre una hoja "Galería (fotos)" / "PDF". Fotos con `image_picker` (multi); cada una se normaliza con OpenCV (en vez de `flutter_exif_rotation`, que no compila con AGP 9.1) y pasa por recorte → filtros. Probado: 2 fotos con EXIF 6 y 8 quedaron rectas y como páginas 4 y 5; cancelar una foto borra su archivo.
- [x] 1.2 Importar PDF: `file_picker` + `pdfx`; todas las páginas a JPEG (1415×2000 en la prueba), sin recorte, en orden; diálogo "Importando PDF… n/N". Probado con un PDF de 3 páginas (tardó < 1 s, el diálogo casi no se ve).
- [x] 2.1 Rotar: botón en el visor; dos rotaciones = `_r180`; `session.json` apunta al nuevo archivo; persiste tras cerrar y reabrir; OCR usa el archivo rotado.
- [x] Renombrar documento: menú de Home y lápiz en Páginas; `"title"` en `session.json`; vacío restaura la fecha. Probado "Contrato renta" y persistencia tras reiniciar.
- Dependencias nuevas: `image_picker ^1.2.4`, `file_picker ^13.1.0`, `pdfx ^2.11.0`. Sin cambios en Manifest ni Gradle.
- Pendiente de la Parte 1: el fallback de `loadAll` sin `session.json` no reconoce archivos `_rN` (perdería rotaciones); PDFs con contraseña muestran "No se pudo importar el PDF."; `retrieveLostData` de image_picker no está manejado.

### Parte 2 — 1.3 modos de captura y composición de ID (HECHA Y PROBADA)

- [x] Chips Docs / ID / Tarjeta / Diapositivas sobre el obturador (`CaptureMode` en `models/capture_mode.dart`); el marco (`DocumentGuidePainter(ratio:)`) y el texto de ayuda cambian por modo. Probado: 0.707, 1.586 y 16:9 se dibujan dentro del preview. Los chips son `Material` + `InkWell` propios porque `ChoiceChip` de Material 3 ignoraba el color en tema claro.
- [x] Modo ID: frente → recorte (sin filtros) → "Ahora el reverso" + botón "Cancelar ID" → reverso → recorte → `IdComposer.compose` (A4 2480×3508 blanca, margen 8 %, etiquetas "Frente"/"Reverso" en gris, ROI con `region` + `copyTo`) → `page_N_id.jpg` → Filtros → una sola `ScanPage`. Probado con empaque + tarjeta: página compuesta recta y legible, `session.json` = `page_1_id.jpg`, la cámara vuelve a "esperando frente".
- [x] Arrastrar esquinas en el recorte (se probó aquí por primera vez): funciona; ojo con los handles pegados al borde derecho, donde el gesto "atrás" de Android se come el toque (hay que tomarlos desde ~40 px más adentro).
- Decisión: cambiar de chip mientras hay un frente pendiente lo descarta (borra `page_N.jpg` y su recorte).

### Parte 3 — 1.4 disparo automático (HECHA Y PROBADA)

- [x] Toggle en la barra superior ("Disparo automático"). `startImageStream` con `ImageFormatGroup.yuv420`; cada ~700 ms el plano Y → Mat gris (`Mat.fromVec`, respeta `bytesPerRow`) → 320 px → `DocumentDetector.detectQuadInGray` (core extraído, también usado por el recorte). Esquinas normalizadas; 3 análisis consecutivos con ±4 % disparan `_capture()`; el stream se detiene al disparar y se re-arma con contador en cero al volver.
- [x] Probado en el S10+ (frames 1440×1080): con una nota de venta a ~25 cm disparó tras 3 análisis estables, el recorte detectó la hoja, al volver no volvió a disparar sin nueva estabilización, al apagar el toggle el stream se detiene y el obturador manual sigue funcionando.
- Decisión: el umbral de área quedó en **20 %** (la especificación decía 35 %): el porcentaje se mide sobre el cuadro completo del sensor (4:3), más ancho que lo que se ve en pantalla, y con 35 % solo disparaba pegando mucho la cámara. Objetos con muescas (el empaque de pilas) no dan cuadrilátero y no disparan: es comportamiento esperado.
- [ ] No probado: segundo plano con el stream activo, linterna con stream, ID con disparo automático.

### Parte 4 — 2.2 anotaciones (HECHA Y PROBADA)

- [x] `AnnotateScreen` desde el visor ("Anotar"): Texto (diálogo, arrastrable), Resaltado (rectángulo amarillo 35 %, arrastrable/redimensionable), Lápiz (trazo negro 4 px), Firma (panel blanco → imagen transparente abajo a la derecha, arrastrable y con pinch) y Deshacer. Las anotaciones viven en píxeles de la imagen; guardar renderiza con `PictureRecorder` + el mismo painter a resolución real (máx. 3000 px) → `<base>_annotated.png` y actualiza `currentPath`. `PopScope` pregunta "¿Salir sin guardar?".
- [x] Probado en el S10+: texto, resaltado, lápiz, deshacer y firma se ven en el PNG final (1415×2000), `session.json` apunta a `page_1_annotated.png`, la miniatura en Páginas se actualiza y el PDF embebe el PNG.
- Bug corregido durante la prueba: el tamaño del texto se calculaba después del diálogo, cuando el teclado ya había reducido el lienzo, y salía al doble; ahora se captura la escala antes de abrir el diálogo.
- `PageEditor.ocrTextPath` reemplaza `.jpg/.jpeg/.png` por `_ocr.txt` y lo usan OCR y PDF. Anotar una página ya anotada sobrescribe el PNG y borra su `_ocr.txt` viejo.
- [ ] No probado: pinch de la firma, redimensionar el resaltado por esquinas, mover anotaciones, tiempo de guardado con fotos de 12 MP.

### Parte 5 — 2.3 selección, duplicar, mover, copiar, extraer, eliminar (HECHA Y PROBADA)

- [x] Modo selección en `PagesScreen` (ícono de lista o long-press): checkboxes, "N seleccionadas", seleccionar todo, barra inferior Duplicar / Mover / Copiar / Extraer / Eliminar. `PageManager` numera las copias con `max(page_N)+1` leído de los archivos, copia el `_ocr.txt` si existe, guarda ambos `session.json` antes de borrar archivos y borra la carpeta si la sesión queda vacía. Hoja de destino con "Documento nuevo" + los demás escaneos.
- [x] Probado: duplicar (→ `page_6.jpg`), mover al documento de la ID (salió del origen con sus archivos y entró como `page_3.jpg`), extraer a documento nuevo, copiar a documento nuevo, eliminar con confirmación; Home refleja los conteos.
- Decisión: el modo selección solo está disponible al abrir desde Home (`allowPageManagement`), no desde la miniatura de la cámara, porque la cámara numera con su propio contador y chocaría.
- Renombrar y reordenar siguen persistiendo en `session.json`.

### Parte 6 — 2.4 opciones de PDF (HECHA Y PROBADA)

- [x] "Crear PDF" abre "Opciones del PDF": switch OCR (default ON), switch Comprimir (default ON: JPEG calidad 72, máx. 2000 px, también para PNG anotados), campo Marca de agua (diagonal 45°, gris 15 %, Latin-1), switch Proteger con contraseña + campo (valida vacío). Cifrado AES-256 con `syncfusion_flutter_pdf` (`PdfDocument(inputBytes:)` → `security.userPassword/ownerPassword` → `save()`). Nombre y `Printing.sharePdf` sin cambios; botón "Generando PDF…".
- Dependencia nueva: `syncfusion_flutter_pdf ^35.1.40+1` (licencia Community: gratis para individuos y empresas pequeñas; revisar antes de publicar).
- [x] Probado en el S10+ (PDFs verificados en la PC con pypdf/pymupdf): el diálogo aparece al tocar "Crear PDF"; con defaults el PDF baja de 732 KB a 376 KB y la página anotada (PNG) va como JPEG; marca de agua "CONFIDENCIAL" diagonal y tenue en las 3 páginas; con contraseña vacía muestra "Escribe una contraseña." y no cierra; con contraseña el PDF queda cifrado (sin ella no abre, con ella sí); sin OCR y sin comprimir exporta con las imágenes originales (732 KB, PNG intacto); con el teclado abierto el diálogo se desplaza sin desbordar.
- [ ] No probado: abrir el PDF cifrado en un visor del teléfono (Adobe/Drive) y que pida la contraseña ahí; tiempos con muchas páginas.

### Estado general (2026-10-17, 18:35)

Bloques 1 y 2 completos: Partes 1–6 implementadas y verificadas en el Galaxy S10+ (Android 12). `flutter analyze` sin issues; último APK: `build/app/outputs/flutter-apk/app-debug.apk`. Trazas temporales del disparo automático ya retiradas.

## 11. Mejoras (plan del 2026-10-17, segunda tanda)

Dispositivo de pruebas: Galaxy S10+ (Android 12). Cada parte se prueba antes de pasar a la siguiente.

### Parte A — correcciones (HECHA Y PROBADA)

- [x] Orientación bloqueada en vertical (`main.dart` + `android:screenOrientation="portrait"`). Probado forzando rotación horizontal: la ventana se queda en ROTATION_0.
- [x] Recorte: margen de 24 px horizontales / 16 verticales alrededor de la imagen y radio de imán 64 px; las esquinas ya no caen en la zona del gesto "atrás".
- [x] Háptica: tic al enganchar el documento (disparo automático), vibración media al disparar solo, ligera en el obturador manual.
- [x] `retrieveLostData` en Home: si Android mató la app durante el selector, las fotos se importan a una sesión nueva (sin recorte) con snackbar "Se recuperaron N fotos.". Prueba manual: Opciones de desarrollador → "No mantener actividades" → cámara → galería → elegir → volver. No probado en dispositivo.
- [x] `session.json` lleva `"version": 1`; el loader ignora llaves desconocidas.
- [x] Loader sin `session.json` reconstruye rotaciones, anotaciones e IDs (elige el derivado más nuevo; salta el reverso de una ID). Probado borrando los json de dos documentos: ambos volvieron completos; solo se pierde el título.
- [x] `SessionStore.cleanup`: tras rotar, anotar, borrar o mover borra derivados sin referencia (`_rNN`, filtros, previews, `_ocr` huérfanos) con 30 s de gracia; nunca toca `page_K.jpg`, `_crop`, `_id`, `session.json` ni rutas referenciadas. Probado: tras rotar quedó solo `_r270`.
- [x] PDF con el título del documento: `Contrato_renta.pdf` (sanitizado, máx. 60); sin título sigue `Escaneo_fecha.pdf`. Probado.
- `SessionStore.storageBytes()` existe pero aún no tiene UI.

### Parte B — visor con swipe y lupa (HECHA Y PROBADA)

- [x] `PhotoViewerScreen(session, initialIndex)`: `PageView` con "Página X de N"; Rotar/Anotar/Extraer texto sobre la página visible; tras rotar o anotar se refresca sin cerrar. Zoom con `InteractiveViewer` por página; el `PageView` se bloquea mientras hay zoom y el paneo solo se habilita con zoom (`panEnabled: _zoomed`); sin eso el visor se comía el swipe (bug encontrado en la prueba).
- [x] Lupa en el recorte: círculo de 130 px arriba del dedo (abajo si no cabe), imagen 2.5× centrada en la esquina activa, cruz teal, `IgnorePointer`. Probado: aparece al arrastrar y desaparece al soltar.

### Parte C — capa OCR alineada por palabra (HECHA Y PROBADA)

- [x] `OcrService.recognizeDetailed` devuelve texto + palabras con `boundingBox` (ML Kit `blocks → lines → elements`) y el tamaño de la imagen leído del encabezado (`ImageDescriptor`, sin decodificar). `OcrScreen` escribe `_ocr.txt` y `_ocr.json`.
- [x] `PdfService`: con JSON válido dibuja cada palabra invisible en su sitio (mismo cálculo `contain` + margen 16 pt; fontSize = 0.8·alto, 2–40 pt; un solo `pw.Opacity(0)` por página). Sin JSON pero con `.txt` → bloque de 6 pt como antes. Las coordenadas usan el ancho/alto del JSON, así que la compresión no las desplaza.
- [x] Rotar y anotar borran los sidecars `_ocr.*` (`PageEditor.deleteOcrSidecars`).
- [x] Script de verificación: `python tool/check_ocr_layer.py <pdf> <page_ocr.json> [--password P]` compara el centro esperado de cada palabra contra el que extrae pymupdf; termina con 0 si ≥ 90 % cae dentro del 5 % del ancho de página.
- [x] Probado en el S10+: OCR de una página impresa (93 palabras, JSON 1415×2000) → PDF → bajados con adb. pymupdf encuentra 92 palabras en esa página y ninguna en las que no tienen OCR. Centros dentro del 5 % del ancho de página: 98 % con comparación por cercanía; 87 % con el script, que además exige que el texto coincida token a token (pymupdf parte distinto `OCR.`/`2:`). El corrimiento horizontal en palabras largas (hasta ~20 pt) viene de que Helvetica es más angosta que la caja del OCR. Comando: `python tool/check_ocr_layer.py Contrato_renta.pdf page_2_ocr.json --page 2`.

### Parte D — trabajo pesado fuera del hilo de UI (HECHA, probada en parte)

- [x] PDF: preparación en UI (compresión OpenCV async + lectura de `_ocr.*` a objetos planos `PdfJob/PdfPageInput/PdfWord`) y render + cifrado dentro de `Isolate.run`; el archivo se escribe en UI. Probado: PDF de 3 páginas con capa OCR generado en < 1 s con el spinner "Generando PDF…".
- [x] Filtros (`buildPreview`/`export`), detección y warp del recorte, composición de ID e importación de imágenes usan las variantes `*Async` de OpenCV; se quitaron los `delay` artificiales de 60/80 ms. Quedan síncronos por diseño: `createCLAHE` (solo construye el objeto; `applyAsync` sí), `contourArea/arcLength/approxPolyDP` (microsegundos por contorno) y el detector del stream en vivo.
- [x] Guardar anotación: `toImage`/`toByteData(png)` ya corren en el motor fuera del hilo Dart; no hace falta isolate.
- [x] `PageManager._copyPage` copia también `_ocr.json`.
- [ ] No medido en dispositivo: fluidez de la fila de chips al aplicar "Mejorar" sobre una foto de 12 MP, y PDF de 10+ páginas.

### Parte E — cuadro en vivo, modo lote, búsqueda, exportación (HECHA Y PROBADA)

- [x] Cuadro en vivo: con disparo automático activo se dibuja el cuadrilátero detectado (blanco mientras rastrea, teal al estabilizar). Mapeo sensor → pantalla: rotación por `sensorOrientation` (90: `(1−y, x)`) y el mismo "cover" que el preview (`FittedBox` sobre `previewSize` girado). Probado en el S10+ sobre la nota de venta: coincide con el papel.
- [x] Modo lote ("Lote", `burst_mode`): tras cada disparo (manual o automático) recorta solo con `detectOrNull` + `applyWarp` y aplica el último filtro usado (`FilterScreen.lastUsed`, inicial Mejorar); si no detecta, cae al flujo normal. Pastilla "Lote · Mejorar" y snackbar "Página N lista". Probado: 6 páginas procesadas sin tocar nada, `page_N_crop_enhance.jpg` nítidas.
- [x] Cooldown del disparo automático (bug encontrado en la prueba): con la hoja quieta disparaba cada ~2 s. Ahora guarda el cuadro del último disparo y no vuelve a disparar hasta que el cuadro se mueva más del 8 % o desaparezca. Probado: 14 s quieto → 1 sola página.
- [x] Búsqueda en Home sobre los `_ocr.txt` (y títulos): sin acentos ni mayúsculas, debounce 300 ms, fragmento con la coincidencia en negritas, "N coincidencias"/"Sin coincidencias.", aviso si no hay OCR. Probado: "PRUEBA" → Contrato renta · Página 2.
- [x] "Espacio usado: X MB" al pie de la lista (`storageBytes`). Probado: 14.1 MB.
- [x] Exportación: el diálogo del PDF tiene "Compartir" / "Guardar en el teléfono" (`FilePicker.saveFile` con `mimeType: application/pdf`, diálogo "guardar como" del sistema); menú ⋮ "Compartir como imágenes" y acción "Compartir" en selección (share_plus, máx. 30). Dependencia nueva: `share_plus ^13.3.1`. [ ] Guardar en Descargas y compartir imágenes no probados en dispositivo (la otra sesión está usando el teléfono).

### Parte F — build de release firmado (HECHA Y PROBADA)

- [x] Keystore de subida nuevo fuera del proyecto: un archivo `.jks` guardado FUERA del repositorio (RSA 2048, alias `escaner`, 10000 días). Contraseña y alias anotados junto al keystore, nunca en el repo. **Respaldarlo**: si se pierde no se puede actualizar la app en Play.
- [x] `android/key.properties` (ignorado por `android/.gitignore`) y `signingConfigs.release` en `android/app/build.gradle.kts`; si falta `key.properties`, el release cae a la firma debug.
- [x] `android/app/proguard-rules.pro`: `-dontwarn` para los reconocedores ML Kit chino/japonés/coreano/devanagari (R8 fallaba porque el plugin los referencia y solo incluimos el latino) y `-keep` de `com.google.mlkit.**`, `gms.internal.mlkit_*` y los `ComponentRegistrar` de Firebase. Sin los `-keep`, el release compilaba pero el OCR tronaba (`NoSuchMethodException` en `TextRegistrar.<init>`): R8 borraba los constructores que ML Kit usa por reflexión.
- [x] `flutter build appbundle --release --target-platform android-arm64` → `app-release.aab` 44.3 MB. `flutter build apk --release --target-platform android-arm64` → `app-release.apk` 61.4 MB (la mayor parte es OpenCV nativo). Firma verificada: APK con apksigner (esquema v2) y AAB con jarsigner; ambos `CN=AppScanner`, SHA-256 `6B:AC:24:B4:…:6C:93`, igual al keystore.
- [x] Instalado en el S10+ (se desinstaló la debug: firma distinta → `INSTALL_FAILED_UPDATE_INCOMPATIBLE`; se borraron los escaneos de prueba). Probado en release: arranque sin crash, cámara + recorte (OpenCV nativo), importar PDF de 3 páginas (pdfx) y OCR con texto correcto. Flags del paquete sin `DEBUGGABLE`.
- Nota: con el release instalado ya no sirve `adb shell run-as` (no es depurable); para volver a probar con debug hay que desinstalar el release (y se borran los datos otra vez).
- applicationId `com.pedro.escaner`, versión `1.0.0+1` y nombre "AppScanner" sin cambios.

Checklist de publicación (Play Console):
- [ ] Cuenta de desarrollador de Google Play (pago único, verificación de identidad).
- [ ] Crear la app con el applicationId definitivo (después ya no se cambia) y activar Play App Signing subiendo el AAB firmado con la clave de subida.
- [ ] Ficha: nombre, descripción corta y larga, ícono 512×512, imagen destacada 1024×500, mínimo 2 capturas de teléfono.
- [ ] Política de privacidad publicada en una URL (la app usa cámara y archivos locales; nada sale del teléfono).
- [ ] Formulario de Seguridad de los datos: sin recolección ni compartición de datos; procesamiento solo en el dispositivo.
- [ ] Clasificación de contenido, público objetivo y declaración de anuncios (sin anuncios).
- [ ] Revisar la licencia Community de `syncfusion_flutter_pdf` (gratis solo para individuos/empresas pequeñas).
- [ ] Prueba interna o cerrada antes de producción (Google exige pruebas cerradas con testers para cuentas personales nuevas).


### Publicación en GitHub (2026-10-18)

- Repositorio público con licencia MIT: https://github.com/Pedrovbm1/appscanner
- Release v1.0.0 con `AppScanner-v1.0.0.apk` (44 MB, solo arm64, versionCode 1, firmado con la clave de subida). Probado en el S10+: instala encima de la versión anterior conservando el historial; arranque, cámara y OCR sin errores.
- Hallazgo: el plugin de Flutter siempre declara arm64, armeabi-v7a y x86_64, aunque se compile solo para arm64, porque varios plugins traen librerías de 32 bits. Un teléfono de 32 bits instalaría ese APK y se cerraría al abrirlo. Se resuelve con `--split-per-abi`; `force-version-code-ignoring-abi=true` evita que la versión pase a 2001 y bloquee actualizar después desde Play. Comando completo en el README.
- Capturas y texto para redes en `docs/capturas/` (documentos de ejemplo inventados).

### Versión 1.0.1 (2026-10-18) — correcciones reportadas por uso real

- **Vista previa completa (contain):** antes la vista previa usaba "cover" y en pantallas altas mostraba solo ~61 % del ancho de la foto; el usuario encuadraba la hoja y la foto salía con mucho más alrededor. Ahora se ve el cuadro completo del sensor, igual a lo que se guarda; el marco guía y el contorno en vivo se dibujan relativos a ese rectángulo.
- **Detector nuevo:** el anterior (Canny 60/180 fijo, solo 4 vértices exactos, área ≥ 15 %) falló en 7 de 8 escenas de prueba y en la foto real del usuario (hoja sobre cobija roja). El nuevo combina: una máscara de "papel" (brillo menos 1.2 × saturación con Otsu) para elegir cuál figura es la hoja, contornos de bordes con umbrales adaptativos a la mediana y casco convexo para ubicar esquinas, rechazo de figuras pegadas a la orilla y puntuación por contraste dentro/fuera. En la PC: 8/8 escenas con error < 2 %, sin falsos positivos en una escena sin documento, y la foto real del usuario detectada. La detección del recorte corre en un isolate; la de la cámara en vivo usa solo bordes sobre el plano Y.
- **Botones de volumen:** el manejador de Flutter no recibía las teclas en Samsung (aparecía el panel de volumen). Se interceptan en `MainActivity.dispatchKeyEvent` solo cuando la cámara está al frente (canal `escaner/volume_keys`, activado y desactivado con un `RouteObserver`). Probado en el S10+: toma la foto y el volumen no cambia.
- **Interruptores recordados:** disparo automático y modo lote se guardan en `camera_settings.json`.
- Probado por Pedro en el S10+ con su hoja: funciona.
