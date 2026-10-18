# Texto para publicar

Imágenes en esta carpeta, en orden: `00_portada.jpg` y luego `01` a `11`. Formato 1080×1350 (vertical, sirve para Instagram, Facebook y LinkedIn). Todos los documentos que aparecen son de ejemplo, inventados para las capturas.

---

## Versión corta (Instagram / Facebook / WhatsApp)

📄 Hice mi propia app para escanear documentos: **AppScanner**.

Tomas la foto, la app encuentra la hoja sola, la endereza y la limpia. Después puedes sacarle el texto, anotarla, firmarla y exportarla a PDF.

✅ Recorte automático con lupa
✅ Filtros para que se vea como escaneado de verdad
✅ Modo credencial: frente y reverso en una sola hoja
✅ Disparo automático cuando la hoja está quieta
✅ Reconoce el texto y lo puedes buscar
✅ Anota, resalta y firma
✅ PDF con marca de agua o contraseña

🔒 Todo se procesa en tu teléfono. Sin cuentas, sin anuncios, sin mandar tus documentos a ningún servidor.

Es gratis y de código abierto 👉 github.com/Pedrovbm1/appscanner

#Flutter #Android #CodigoAbierto #OpenSource

---

## Versión larga (LinkedIn / blog)

Construí **AppScanner**, un escáner de documentos para Android hecho con Flutter, y lo publiqué como código abierto.

La idea: que escanear un contrato, una credencial o una cotización no dependa de apps llenas de anuncios que suben tus documentos a la nube. AppScanner hace todo en el teléfono.

**Qué hace**
- **Captura inteligente:** detecta los bordes de la hoja y corrige la perspectiva. Tiene modos para documentos, credenciales (frente y reverso en una hoja), tarjetas y diapositivas, disparo automático cuando la hoja está quieta y modo lote para escanear muchas hojas seguidas.
- **Edición:** recorte con lupa, siete filtros (incluido uno que quita sombras), rotar, y anotaciones con texto, resaltado, lápiz y firma.
- **Texto:** OCR en el dispositivo con ML Kit. El texto se puede copiar y buscar desde el inicio de la app.
- **Organización:** historial, renombrar, reordenar, duplicar, mover y copiar páginas entre documentos.
- **PDF:** con capa de texto alineada palabra por palabra (el PDF se puede buscar y seleccionar), compresión, marca de agua y protección con contraseña AES-256.

**Cómo está hecho**
Flutter y Dart, OpenCV para la visión por computadora (detección de bordes, perspectiva y filtros), Google ML Kit para el reconocimiento de texto y el paquete `pdf` para generar los documentos. El trabajo pesado corre fuera del hilo de la interfaz para que la app no se trabe.

Código bajo licencia MIT: github.com/Pedrovbm1/appscanner

---

## Descripción de cada imagen

| Imagen | Título | Descripción |
|---|---|---|
| 00_portada | AppScanner | Escáner de documentos para Android. Todo en tu teléfono, gratis y de código abierto. |
| 01_inicio | Todos tus escaneos en un lugar | Historial guardado, búsqueda por el texto de tus documentos y el espacio que ocupan. |
| 02_modos | Modos para cada documento | Docs, ID, Tarjeta o Diapositivas. En modo ID captura frente y reverso y los acomoda en una sola hoja. |
| 03_deteccion | Detecta la hoja sola | Encuentra los bordes aunque la foto salga chueca y corrige la perspectiva. |
| 04_lupa | Ajuste fino con lupa | Al arrastrar una esquina aparece una lupa para recortar justo en el borde. |
| 05_filtros | Filtros que lo dejan legible | Mejorar, Grises, Blanco y negro, Aclarar y Sin sombra. |
| 06_ocr | Reconoce el texto | OCR en el dispositivo, con acentos; no se manda nada a internet. |
| 07_anotar | Anota y firma | Texto, resaltado, lápiz y firma, con deshacer. |
| 08_paginas | Organiza tus páginas | Reordena, duplica, mueve, copia, extrae o comparte páginas. |
| 09_pdf | PDF a tu medida | Comprimido, con marca de agua o con contraseña; compartir o guardar. |
| 10_busqueda | Encuentra cualquier documento | Busca una palabra y te dice en qué documento y página está. |
| 11_importar | Importa lo que ya tienes | Trae fotos de la galería o PDFs existentes. |
