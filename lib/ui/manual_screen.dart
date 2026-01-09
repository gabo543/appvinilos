import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'app_logo.dart';

/// Manual de uso dentro de la app.
///
/// Objetivo: explicar pantallas, botones y flujos, con iconos.
class ManualUsoScreen extends StatelessWidget {
  const ManualUsoScreen({super.key});

  Widget _sectionTitle(BuildContext context, IconData icon, String title, {String? subtitle}) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.82)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(title),
                  style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.2),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    context.tr(subtitle),
                    style: t.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.70),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(BuildContext context, {required IconData icon, required String title, required String desc}) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(context.tr(title), style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(
        context.tr(desc),
        style: t.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.75), fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _step(BuildContext context, int n, String title, String desc) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.primary.withOpacity(0.35)),
            ),
            child: Text('$n', style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(title), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  context.tr(desc),
                  style: t.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.78), fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        title: appBarTitleTextScaled(context.tr('Manual de uso'), padding: const EdgeInsets.only(left: 8)),
        titleSpacing: 12,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // HERO
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.onSurface.withOpacity(0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GaBoLP', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  context.tr('Tu colección de vinilos, simple y rápida.'),
                  style: t.textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.72), fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    'Esta app sirve para registrar tu colección (LPs), mantener una lista de deseos, y ayudarte a encontrar datos (discografías) y precios en tiendas seleccionadas.',
                  ),
                  style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _sectionTitle(
            context,
            Icons.lightbulb_outline,
            '¿Para qué sirve la app?',
            subtitle: 'Qué puedes hacer con GaBoLP en el día a día.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
              child: Column(
                children: [
                  _actionRow(
                    context,
                    icon: Icons.library_music,
                    title: 'Llevar tu colección',
                    desc: 'Guarda artista, álbum, año, formato y condición. Puedes ver por lista, grilla o agrupado por artista.',
                  ),
                  _actionRow(
                    context,
                    icon: Icons.shopping_cart_outlined,
                    title: 'Lista de deseos',
                    desc: 'Anota LPs que quieres comprar, su estado (por comprar/comprado) y revisa precios cuando lo necesites.',
                  ),
                  _actionRow(
                    context,
                    icon: Icons.qr_code_scanner,
                    title: 'Agregar rápido',
                    desc: 'Puedes agregar por código de barras, por foto de la carátula (texto) o ingresando a mano.',
                  ),
                  _actionRow(
                    context,
                    icon: Icons.storefront_outlined,
                    title: 'Comparar precios y alertas',
                    desc: 'Consulta tiendas activadas y crea alertas: “Avísame si baja de…”.',
                  ),
                  _actionRow(
                    context,
                    icon: Icons.backup_outlined,
                    title: 'Backup y exportación',
                    desc: 'Guarda/importa backups, comparte el archivo y exporta inventario a CSV o PDF.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          _sectionTitle(
            context,
            Icons.grid_view_outlined,
            'Pantallas principales',
            subtitle: 'Dónde está cada cosa.',
          ),
          Card(
            child: Column(
              children: [
                _actionRow(context, icon: Icons.home_outlined, title: 'Inicio', desc: 'Atajos rápidos: Buscar, Discografías, Ajustes, y acceso a tus listas.'),
                const Divider(height: 1),
                _actionRow(context, icon: Icons.list_alt_outlined, title: 'Vinilos', desc: 'Tu lista completa. Filtra, ordena y abre la ficha de cada disco.'),
                const Divider(height: 1),
                _actionRow(context, icon: Icons.star_border, title: 'Favoritos', desc: 'Vinilos marcados con ⭐ para tenerlos a mano.'),
                const Divider(height: 1),
                _actionRow(context, icon: Icons.shopping_cart_outlined, title: 'Deseos', desc: 'Tu wishlist. Útil para planificar compras y revisar precios.'),
                const Divider(height: 1),
                _actionRow(context, icon: Icons.delete_outline, title: 'Borrar / Papelera', desc: 'Envía a papelera para recuperar después o eliminar definitivo.'),
                const Divider(height: 1),
                _actionRow(context, icon: Icons.settings_outlined, title: 'Ajustes', desc: 'Backup, exportaciones, tiendas, alertas, apariencia y mantenimiento.'),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _sectionTitle(
            context,
            Icons.touch_app_outlined,
            'Botones y qué hacen',
            subtitle: 'Referencia rápida (con iconos).',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 12),
              child: Column(
                children: [
                  _actionRow(context, icon: Icons.search, title: 'Buscar', desc: 'Busca en tu colección por artista o álbum.'),
                  _actionRow(context, icon: Icons.library_music, title: 'Discografías', desc: 'Busca un artista, revisa álbumes y agrega a Lista o Deseos.'),
                  const Divider(height: 10),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: Row(
                      children: [
                        Icon(Icons.library_music, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.tr('Discografías: iconos'),
                            style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _actionRow(
                    context,
                    icon: Icons.visibility,
                    title: 'Ojo (filtros)',
                    desc: 'Muestra u oculta los buscadores de Álbum y Canción para tener más espacio.',
                  ),
                  _actionRow(
                    context,
                    icon: Icons.saved_search,
                    title: 'Plan Z (escaneo local)',
                    desc: 'Escanea tracklists ya cargados para encontrar en qué álbumes aparece la canción escrita (sin internet).',
                  ),
                  _actionRow(
                    context,
                    icon: Icons.explore,
                    title: 'Brújula (Explorar)',
                    desc: 'Descubre discos por género, país y años. Desde ahí puedes abrir la ficha y agregar a Deseos.',
                  ),
                  _actionRow(
                    context,
                    icon: Icons.hub_outlined,
                    title: 'Similares',
                    desc: 'Muestra artistas relacionados al artista seleccionado y te lleva a su discografía.',
                  ),
                  _actionRow(context, icon: Icons.add, title: 'Agregar', desc: 'Agregar por escáner, carátula o a mano.'),
                  _actionRow(context, icon: Icons.qr_code_scanner, title: 'Escanear (código de barras)', desc: 'Lee UPC/EAN para encontrar el álbum más exacto.'),
                  _actionRow(context, icon: Icons.photo_camera_outlined, title: 'Leer carátula (foto)', desc: 'Toma una foto y la app intenta leer artista y álbum.'),
                  _actionRow(context, icon: Icons.hearing_outlined, title: 'Escuchar', desc: 'Reconoce una canción (requiere token AudD configurado en Ajustes).'),
                  _actionRow(context, icon: Icons.star, title: 'Favorito', desc: 'Marca/desmarca un vinilo como destacado.'),
                  _actionRow(context, icon: Icons.storefront_outlined, title: 'Precios', desc: 'Muestra precios en tiendas activadas. Los rangos son orientativos.'),
                  _actionRow(context, icon: Icons.notifications_active_outlined, title: 'Alerta de precio', desc: 'Configura un objetivo: te avisará cuando encuentre un precio bajo ese valor.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          _sectionTitle(
            context,
            Icons.route_outlined,
            'Flujo recomendado',
            subtitle: 'Una forma simple de usar la app sin perderte.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  _step(context, 1, 'Agregar un disco', 'Usa Escanear, Leer carátula o Agregar a mano. Revisa los datos antes de guardar.'),
                  _step(context, 2, 'Abrir la ficha', 'Toca el vinilo para ver detalles. Desde ahí puedes editar, marcar favorito o ver canciones.'),
                  _step(context, 3, 'Wishlist', 'Si aún no lo tienes, agrégalo a Deseos y define estado (por comprar / comprado).'),
                  _step(context, 4, 'Precios y alertas', 'En Deseos puedes revisar precios y crear una alerta “Avísame si baja de…”.'),
                  _step(context, 5, 'Backup', 'En Ajustes activa Guardado automático o usa Guardar backup de vez en cuando.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          _sectionTitle(
            context,
            Icons.info_outline,
            'Notas importantes',
            subtitle: 'Detalles que evitan sorpresas.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('• Precios: se muestran solo como referencia. Algunas tiendas cambian valores o bloquean consultas automáticas.'),
                    style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('• AppVinilos: los precios/alertas se basan en Vinilo 12" LP (LP, 2LP, 3LP, 4LP). Se excluyen EP, 7", singles y otros formatos.'),
                    style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('• Exportar manual: en Ajustes > Ayuda puedes exportar este manual a PDF para compartirlo o imprimirlo.'),
                    style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }
}
