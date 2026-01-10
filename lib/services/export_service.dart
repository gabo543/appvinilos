import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../l10n/app_strings.dart';

import '../db/vinyl_db.dart';

class ExportService {
  static Future<pw.ThemeData> _pdfTheme() async {
    // Fuente con buen soporte de acentos y símbolos (evita cuadrados en PDF).
    final base = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
    return pw.ThemeData.withFont(base: base, bold: bold);
  }

  static String _csvEscape(String s) {
    final needsQuotes = s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r');
    var out = s.replaceAll('"', '""');
    if (needsQuotes) out = '"$out"';
    return out;
  }

  static String _codeFromRow(Map<String, dynamic> v) {
    final a = v['artistNo'];
    final b = v['albumNo'];
    if (a == null || b == null) return '';
    return '${a.toString()}.${b.toString()}';
  }

  static String _nowStamp() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}';
  }

  /// Exporta tu colección (vinyls) a CSV.
  ///
  /// Se guarda usando el selector del sistema (igual que el backup JSON), para evitar
  /// problemas de permisos en Android moderno.
  static Future<String?> exportCsvInventory() async {
    final all = await VinylDb.instance.getAll();

    final headers = [
      'Codigo',
      'Artista',
      'Album',
      'Anio',
      'Genero',
      'Pais',
      'Condicion',
      'Formato',
      'Favorito',
    ];

    final lines = <String>[];
    lines.add(headers.join(','));

    for (final v in all) {
      final fav = (v['favorite'] == 1) ? 'Si' : 'No';
      final row = [
        _csvEscape(_codeFromRow(v)),
        _csvEscape((v['artista'] ?? '').toString()),
        _csvEscape((v['album'] ?? '').toString()),
        _csvEscape((v['year'] ?? '').toString()),
        _csvEscape((v['genre'] ?? '').toString()),
        _csvEscape((v['country'] ?? '').toString()),
        _csvEscape((v['condition'] ?? '').toString()),
        _csvEscape((v['format'] ?? '').toString()),
        _csvEscape(fav),
      ];
      lines.add(row.join(','));
    }

    // BOM para que Excel abra bien acentos en UTF-8
    final csv = '\uFEFF${lines.join('\n')}';
    final bytes = utf8.encode(csv);

    return FilePicker.platform.saveFile(
      dialogTitle: 'Exportar inventario (CSV)',
      fileName: 'GaBoLP_inventario_${_nowStamp()}.csv',
      bytes: bytes,
      allowedExtensions: const ['csv'],
      type: FileType.custom,
    );
  }

  /// Exporta tu colección a un PDF simple "imprimible".
  static Future<String?> exportPdfInventory() async {
    final all = await VinylDb.instance.getAll();

    final doc = pw.Document(theme: await _pdfTheme());

    final data = <List<String>>[];
    for (final v in all) {
      data.add([
        _codeFromRow(v),
        (v['artista'] ?? '').toString(),
        (v['album'] ?? '').toString(),
        (v['year'] ?? '').toString(),
        (v['format'] ?? '').toString(),
        (v['condition'] ?? '').toString(),
      ]);
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        build: (context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(AppStrings.tRaw('GaBoLP — Inventario'), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text('${AppStrings.tRaw('Total')}: ${all.length}', style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Exportado: ${DateTime.now().toLocal().toString().split('.').first}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 14),
            pw.Table.fromTextArray(
              headers: [AppStrings.tRaw('Cod.'), AppStrings.tRaw('Artista'), AppStrings.tRaw('Álbum'), AppStrings.tRaw('Año'), AppStrings.tRaw('Formato'), AppStrings.tRaw('Cond.')],
              data: data,
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FixedColumnWidth(36),
                1: const pw.FlexColumnWidth(2.2),
                2: const pw.FlexColumnWidth(2.6),
                3: const pw.FixedColumnWidth(28),
                4: const pw.FixedColumnWidth(56),
                5: const pw.FixedColumnWidth(44),
              },
              cellHeight: 16,
            ),
          ];
        },
      ),
    );

    final bytes = await doc.save();

    return FilePicker.platform.saveFile(
      dialogTitle: 'Exportar inventario (PDF)',
      fileName: 'GaBoLP_inventario_${_nowStamp()}.pdf',
      bytes: bytes,
      allowedExtensions: const ['pdf'],
      type: FileType.custom,
    );
  }

  /// Exporta un manual de uso (PDF) para imprimir/compartir.
  ///
  /// Nota: el manual completo con iconos “reales” vive dentro de la app (Ajustes > Ayuda).
  /// En PDF usamos símbolos (cuadritos/emoji simples) para que sea liviano y compatible.
  static Future<String?> exportPdfManual() async {
    final doc = pw.Document(theme: await _pdfTheme());

    pw.Widget h1(String text) => pw.Text(AppStrings.tRaw(text), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold));
    pw.Widget h2(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 6),
          child: pw.Text(AppStrings.tRaw(text), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        );

    pw.Widget bullet(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('•  ', style: const pw.TextStyle(fontSize: 11)),
              pw.Expanded(child: pw.Text(AppStrings.tRaw(text), style: const pw.TextStyle(fontSize: 11))),
            ],
          ),
        );

    pw.Widget iconLine(String icon, String title, String desc) {
      title = AppStrings.tRaw(title);
      desc = AppStrings.tRaw(desc);
      final runes = icon.runes.length;
      final boxW = (runes <= 1) ? 18.0 : 28.0;
      final fs = (runes <= 1) ? 10.0 : 7.5;

      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: boxW,
              height: 18,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey600, width: 0.7),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(icon, style: pw.TextStyle(fontSize: fs)),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text(desc, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        build: (context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                h1(AppStrings.tRaw('GaBoLP — Manual de uso')),
                pw.Text('v5', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              '${AppStrings.tRaw('Guía rápida de pantallas, botones y flujos.')}\n${AppStrings.tRaw('En la app: Ajustes > Ayuda > Manual de uso.')}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 14),

            h2('¿Para qué sirve la app?'),
            bullet('Registrar tu colección de vinilos (LPs) con artista, álbum, año, formato y condición.'),
            bullet('Mantener una lista de deseos (wishlist) para planificar compras.'),
            bullet('Buscar discografías y OST (soundtracks) y agregar discos más rápido (código de barras, carátula o manual).'),
            bullet('Revisar precios en tiendas seleccionadas y crear alertas (“Avísame si baja de…”).'),
            bullet('Respaldar y exportar: backups, CSV y PDF.'),

            h2('Botones y acciones más comunes'),
            iconLine('⌂', 'Inicio', 'Atajos: Buscar, Discografías, Ajustes y acceso a tus listas.'),
            iconLine('⚲', 'Buscar', 'Busca en tu colección por artista o álbum.'),
            iconLine('DIS', 'Discos', 'En Inicio toca Discos para ir a Discografías: busca artistas y álbumes, y agrega a Lista o Deseos.'),
            iconLine('OST', 'OST', 'En Inicio toca OST para buscar bandas sonoras. Al escribir 1–2 letras aparecen sugerencias.'),
            iconLine('+', 'Agregar', 'Agregar por escáner, carátula o a mano.'),
            iconLine('▦', 'Vinilos', 'Tu lista completa: filtra, ordena y abre fichas.'),
            iconLine('★', 'Favoritos', 'Marca vinilos destacados para encontrarlos rápido.'),
            iconLine('☰', 'Deseos', 'Wishlist: pendientes por comprar/comprado + precios/alertas.'),
            h2('Discografías: iconos'),
            iconLine('OJO', 'Ojo (filtros)', 'Muestra u oculta los buscadores de Álbum y Canción para tener más espacio.'),
            iconLine('⚲★', 'Plan Z (escaneo local)', 'Escanea tracklists ya cargados para encontrar en qué álbumes aparece la canción escrita (sin internet).'),
            iconLine('OST', 'OST (Soundtracks)', 'Busca bandas sonoras por título (película/serie/juego) y abre la ficha (canciones) para agregar a Lista o Deseos.'),
            iconLine('EXP', 'Brújula (Explorar)', 'Descubre discos por género, país y años. Desde ahí puedes abrir la ficha y agregar a Deseos.'),
            iconLine('SIM', 'Similares', 'Muestra artistas relacionados al artista seleccionado y te lleva a su discografía.'),

            h2('OST: iconos en resultados'),
            iconLine('LST', 'Lista', 'Agrega el soundtrack a tu colección. Te pedirá condición y formato (LP).'),
            iconLine('FAV', 'Fav', 'Marca como favorito (requiere que el disco exista en tu colección).'),
            iconLine('WIS', 'Deseos', 'Agrega a la wishlist y elige estado (por comprar / comprado).'),
            iconLine('€', '€ (Precios)', 'Busca precios en tiendas activadas para ese soundtrack.'),
            iconLine('V', 'Cuadros / Lista', 'Cambia la vista de resultados entre cards y lista compacta.'),

            iconLine('⚙', 'Ajustes', 'Backup, exportaciones, tiendas, alertas, apariencia y mantenimiento.'),

            h2('Flujo recomendado'),
            bullet('1) Agrega un disco (Escanear / Carátula / A mano).'),
            bullet('2) Abre la ficha y revisa los datos.'),
            bullet('3) Marca ⭐ si es favorito o pásalo a Deseos si aún no lo tienes.'),
            bullet('4) En Deseos, revisa precios y crea alerta si quieres un objetivo.'),
            bullet('5) Guarda backup (manual o automático) para no perder cambios.'),

            h2('Notas importantes'),
            bullet('Precios: son referenciales; algunas tiendas pueden cambiar valores o bloquear consultas.'),
            bullet('AppVinilos: los precios/alertas se basan en Vinilo 12" LP (LP, 2LP, 3LP, 4LP). Se excluyen EP, 7", singles y otros formatos.'),
          ];
        },
        footer: (ctx) {
          return pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Página ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          );
        },
      ),
    );

    final bytes = await doc.save();

    return FilePicker.platform.saveFile(
      dialogTitle: 'Exportar manual (PDF)',
      fileName: 'GaBoLP_manual_${_nowStamp()}.pdf',
      bytes: bytes,
      allowedExtensions: const ['pdf'],
      type: FileType.custom,
    );
  }
}
