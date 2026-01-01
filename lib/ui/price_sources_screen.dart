import 'package:flutter/material.dart';

import '../services/store_price_service.dart';
import '../l10n/app_strings.dart';
import 'app_logo.dart';

/// Ajustes -> Tiendas de precios
///
/// Permite activar/desactivar fuentes de precios (scraping best-effort).
class PriceSourcesScreen extends StatefulWidget {
  const PriceSourcesScreen({super.key});

  @override
  State<PriceSourcesScreen> createState() => _PriceSourcesScreenState();
}

class _PriceSourcesScreenState extends State<PriceSourcesScreen> {
  bool _loading = true;
  Map<String, bool> _enabled = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await StoreSourcesSettings.enabledMap();
    if (!mounted) return;
    setState(() {
      _enabled = m;
      _loading = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.trSmart(msg))),
    );
  }

  Future<void> _reset() async {
    await StoreSourcesSettings.resetToDefaults();
    await _load();
    _snack('Listo ✅');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kAppBarToolbarHeight,
        leadingWidth: appBarLeadingWidthForLogoBack(logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        leading: appBarLeadingLogoBack(context, logoSize: kAppBarLogoSize, gap: kAppBarGapLogoBack),
        title: appBarTitleTextScaled(context.tr('Tiendas de precios'), padding: const EdgeInsets.only(left: 8)),
        titleSpacing: 12,
        actions: [
          IconButton(
            tooltip: context.tr('Restaurar'),
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Column(
                    children: [
                      for (int i = 0; i < StoreSourcesSettings.stores.length; i++) ...[
                        SwitchListTile(
                          value: _enabled[StoreSourcesSettings.stores[i].id] ?? StoreSourcesSettings.stores[i].enabledByDefault,
                          onChanged: (v) async {
                            final id = StoreSourcesSettings.stores[i].id;
                            setState(() => _enabled[id] = v);
                            await StoreSourcesSettings.setEnabled(id, v);
                          },
                          secondary: const Icon(Icons.storefront_outlined),
                          title: Text(StoreSourcesSettings.stores[i].name),
                          subtitle: Text(StoreSourcesSettings.stores[i].description),
                        ),
                        if (i != StoreSourcesSettings.stores.length - 1) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('Los precios pueden cambiar y algunas tiendas pueden bloquear la consulta automática.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
