import 'package:flutter/material.dart';
import '../services/locale_service.dart';

/// Traducción simple ES/EN para toda la app.
///
/// - La app está escrita en Español (ES) por defecto.
/// - Cuando el usuario activa Inglés, se traducen los textos definidos aquí.
/// - Si falta una traducción, se muestra el texto original (ES) para evitar pantallas vacías.
///
/// Nota: mantenemos un diccionario por "texto ES" para que sea fácil añadir traducciones sin
/// tener que inventar keys.
class AppStrings {
  // NOTE: This map intentionally is NOT const.
  // Dart treats duplicate keys as a compile-time error in const maps.
  // Keeping it `final` allows the app to compile even if a translation key
  // is accidentally duplicated (the last value wins).
  static final Map<String, String> _en = <String, String>{
  "2xLP": "2xLP",
  "Abrir ficha del disco": "Open record details",
  "Aceptar": "Accept",
  "Actualizado ✅": "Updated ✅",
  "Actualizar precio": "Update price",
  "Agrega tu primer vinilo para empezar tu colección.": "Add your first record to start your collection.",
  "Agregar": "Add",
  "Agregar a Deseos": "Add to Wishlist",
  "Agregar a Lista": "Add to Collection",
  "Agregar a mano": "Add manually",
  "Agregar a tu lista": "Add to your collection",
  "Agregar a vinilos": "Add to records",
  "Agregar este vinilo": "Add this record",
  "Agregar vinilo": "Add record",
  "Ajusta el contraste del texto.": "Adjust text contrast.",
  "Ajusta fondo y estilo de cards.": "Adjust background and card style.",
  "Algo falló al leer la base de datos. Cierra y vuelve a abrir la app.": "Something went wrong reading the database. Close and reopen the app.",
  "Alerta guardada ✅": "Alert saved ✅",
  "Alerta eliminada ✅": "Alert removed ✅",
  "Alertas de precio": "Price alerts",
  "Tiendas de precios": "Price stores",
  "Activar/desactivar tiendas para comparar precios.": "Enable/disable stores to compare prices.",
  "Aplicar": "Apply",
  "Apunta al código de barras del vinilo.": "Point at the record's barcode.",
  "Aquí aparecerán los vinilos que borres para que puedas recuperarlos.": "Deleted records will appear here so you can restore them.",
  "Artista": "Artist",
  "Artista / Banda": "Artist / Band",
  "Artista o álbum": "Artist or album",
  "Artistas": "Artists",
  "Atrás": "Back",
  "Avísame si baja de": "Notify me if it drops below",
  "Avanzado": "Advanced",
  "Año": "Year",
  "Año (opcional)": "Year (optional)",
  "Año (opcional: corregir)": "Year (optional: fix)",
  "Año desde": "Year from",
  "Año hasta": "Year to",
  "Aún no hay vinilos": "No records yet",
  "A–Z": "A–Z",
  "Borde de tarjetas": "Card border",
  "Boxset": "Box set",
  "Busca el álbum por UPC/EAN.": "Look up the album by UPC/EAN.",
  "Busca un artista para ver su discografía.": "Search an artist to see their discography.",
  "Buscando": "Searching",
  "Buscando en MusicBrainz…": "Searching MusicBrainz…",
  "Buscar": "Search",
  "Explorar": "Explore",
  "Género": "Genre",
  "Ej: Jazz, Rock, Metal": "e.g. Jazz, Rock, Metal",
  "Escribe un género para explorar.": "Type a genre to explore.",
  "Resultados": "Results",
  "Anterior": "Previous",
  "Siguiente": "Next",
  "Buscar precios": "Find prices",
  "Código de barras": "Barcode",
  "Ej: 0190296611964": "e.g. 0190296611964",
  "No pude obtener precios en las tiendas seleccionadas.": "I couldn't get prices from the selected stores.",
  "No hay preview disponible.": "No preview available.",
  "No pude reproducir el preview.": "I couldn't play the preview.",
  "Rango": "Range",
  "Más resultados": "More results",
  "Los precios pueden cambiar y algunas tiendas pueden bloquear la consulta automática.": "Prices can change and some stores may block automatic queries.",
  "Buscar en tu colección…": "Search your collection…",
  "Cambia el contorno de los cuadros.": "Change the card outline.",
  "Cambia el estilo visual de la app.": "Change the app look & feel.",
  "Cambiar cámara": "Switch camera",
  "Cancelar": "Cancel",
  "Precio objetivo": "Target price",
  "Guardar alerta": "Save alert",
  "Quitar alerta": "Remove alert",
  "Revisar alertas": "Check alerts",
  "Sin coincidencias": "No matches",
  "Precio inválido": "Invalid price",
  "Canción": "Song",
  "Canciones": "Tracks",
  "Escribe una canción para filtrar álbumes.": "Type a song to filter albums.",
  "Escribe un álbum para filtrar álbumes.": "Type an album to filter albums.",
  "No encontré esa canción en álbumes.": "I couldn't find that song in albums.",
  "Coinciden": "Matches",
  "Cargar backup local": "Load local backup",
  "Carátula": "Cover",
  "Carátulas": "Covers",
  "Cerrar": "Close",
  "Coincidencia encontrada": "Match found",
  "Color:": "Color:",
  "Compartir backup": "Share backup",
  "Comprado": "Bought",
  "Condición": "Condition",
  "Condición y formato": "Condition & format",
  "Continuar": "Continue",
  "Crea un respaldo completo (colección + deseos + ajustes).": "Create a full backup (collection + wishlist + settings).",
  "Cuadros": "Cards",
  "Cuando agregues vinilos, aquí verás tu colección agrupada por artista.": "Once you add records, you'll see your collection grouped by artist.",
  "Código": "Barcode",
  "Código de barras": "Barcode",
  "Código, carátula o escuchar una canción.": "Barcode, cover, or listen to a song.",
  "Descargando carátulas": "Downloading covers",
  "Descargar carátulas faltantes": "Download missing covers",
  "Deseos (wishlist)": "Wishlist",
  "Detectar / fusionar duplicados": "Detect / merge duplicates",
  "Disco": "Record",
  "Duplicados encontrados": "Duplicates found",
  "EP": "EP",
  "Editar": "Edit",
  "Editar búsqueda": "Edit search",
  "Editar vinilo": "Edit record",
  "Ej: 1973": "e.g. 1973",
  "Ej: Pink Floyd": "e.g. Pink Floyd",
  "Ej: Pink Floyd Animals": "e.g. Pink Floyd Animals",
  "Ej: Rock": "e.g. Rock",
  "Ej: The Dark Side of the Moon": "e.g. The Dark Side of the Moon",
  "Elige la opción que mejor coincida con el texto de la carátula.": "Choose the option that best matches the cover text.",
  "Eliminar": "Delete",
  "Eliminar definitivo": "Delete permanently",
  "Encuentra repetidos por artista+álbum y los fusiona.": "Find duplicates by artist+album and merge them.",
  "Enviar": "Send",
  "Enviar a Drive / WhatsApp / correo.": "Send to Drive / WhatsApp / email.",
  "Enviar a papelera": "Move to trash",
  "Error cargando": "Error loading",
  "Error cargando artistas": "Error loading artists",
  "Escanear": "Scan",
  "Escaneos recientes": "Recent scans",
  "Escanear otro": "Scan another",
  "Aún no hay escaneos.": "No scans yet.",
  "Escribe artista y álbum (opcional: año y género).": "Enter artist and album (optional: year and genre).",
  "Escribe los datos básicos. Luego podrás revisar la ficha y agregar a tu lista o a deseos.": "Enter the basics. Then you can review the details and add it to your collection or wishlist.",
  "Escuchando…": "Listening…",
  "Escuchar": "Listen",
  "Escuchar preview": "Listen to preview",
  "Detener": "Stop",
  "Escuchar y reconocer": "Listen & identify",
  "Estado (wishlist)": "Status (wishlist)",
  "Estado en Deseos": "Wishlist status",
  "Esto deja tus carátulas guardadas para ver offline.": "This keeps your covers saved for offline viewing.",
  "Exportar backup (Descargas)": "Export backup (Downloads)",
  "Exportar inventario (CSV)": "Export inventory (CSV)",
  "Exportar inventario (PDF)": "Export inventory (PDF)",
  "Ayuda": "Help",
  "Guía de pantallas, botones y flujos.": "Guide to screens, buttons and flows.",
  "Manual de uso": "User manual",
  "Explica para qué sirve la app y qué hace cada botón.": "Explains what the app is for and what each button does.",
  "Exportar manual (PDF)": "Export manual (PDF)",
  "Manual listo para imprimir o compartir.": "Print- or share-ready manual.",
  "Discografías: iconos": "Discographies: icons",
  "Ojo (filtros)": "Eye (filters)",
  "Muestra u oculta los buscadores de Álbum y Canción para tener más espacio.": "Show or hide the Album and Song search fields to save space.",
  "Plan Z (escaneo local)": "Plan Z (local scan)",
  "Escanea tracklists ya cargados para encontrar en qué álbumes aparece la canción escrita (sin internet).": "Scans already-loaded tracklists to find which albums contain the typed song (offline).",
  "Brújula (Explorar)": "Compass (Explore)",
  "Descubre discos por género, país y años. Desde ahí puedes abrir la ficha y agregar a Deseos.": "Discover records by genre, country and years. From there you can open details and add to Wishlist.",
  "Similares": "Similar",
  "Muestra artistas relacionados al artista seleccionado y te lleva a su discografía.": "Shows related artists for the selected artist and takes you to their discography.",
  "Soundtracks": "Soundtracks",
  "Busca bandas sonoras por título (película/serie/juego) y abre la ficha para agregar a Lista o Deseos.": "Search soundtracks by title (movie/series/game) and open details to add to Collection or Wishlist.",
  "Escribe un título para buscar.": "Type a title to search.",
  "Ej: Interstellar, Dune, The Last of Us": "e.g. Interstellar, Dune, The Last of Us",
  "Escribe un título para buscar bandas sonoras. Ej: Interstellar, Dune, GTA.": "Type a title to search soundtracks. e.g. Interstellar, Dune, GTA.",
  "Mostrando": "Showing",

  "Filtros": "Filters",
  "Fondo": "Background",
  "Formato": "Format",
  "Fusionar (recomendado)": "Merge (recommended)",
  "Fusionar duplicados": "Merge duplicates",
  "GaBoLP": "GaBoLP",
  "Galería": "Gallery",
  "Guarda portadas para ver offline.": "Save covers for offline viewing.",
  "Guardado automático": "Auto backup",
  "Guardar": "Save",
  "Guardar backup": "Save backup",
  "Guardar, importar y compartir tu colección.": "Save, import and share your collection.",
  "Guárdalo en Descargas para copiarlo o enviarlo.": "Save it to Downloads to copy or share it.",
  "Género (contiene)": "Genre (contains)",
  "Género (opcional)": "Genre (optional)",
  "Importar backup": "Import backup",
  "Ingresar a mano": "Enter manually",
  "Inicio": "Home",
  "Intensidad:": "Intensity:",
  "Inventario listo para imprimir.": "Print-ready inventory.",
  "LP": "LP",
  "Lee artista y álbum desde la portada.": "Read artist and album from the cover.",
  "Lee la carátula (foto)": "Read the cover (photo)",
  "Leyendo carátula y buscando…": "Reading cover and searching…",
  "Limpiar": "Clear",
  "Limpiar texto": "Clear text",
  "Lista (mi colección)": "Collection",
  "Listo": "Done",
  "Lo último que guardaste en tu colección.": "Your most recently saved items.",
  "M (Mint)": "M (Mint)",
  "Mantenimiento y limpieza de tu lista.": "Maintenance and cleanup for your list.",
  "NM (Near Mint)": "NM (Near Mint)",
  "Niveles visuales": "Visual levels",
  "No encontré artistas que coincidan con tu búsqueda.": "I couldn't find artists matching your search.",
  "No encontré coincidencias en tu lista.": "No matches found in your list.",
  "No pude leer el resumen por artista. Cierra y vuelve a abrir la app.": "Couldn't load the artist summary. Close and reopen the app.",
  "No puedo editar: falta ID.": "Can't edit: missing ID.",
  "Opciones básicas y respaldo automático.": "Basic options and auto backup.",
  "Opciones de búsqueda": "Search options",
  "Opciones que pueden reemplazar datos.": "Options that may overwrite data.",
  "Ordenar": "Sort",
  "Otro": "Other",
  "Papelera": "Trash",
  "Papelera vacía": "Trash is empty",
  "Para borrar": "To delete",
  "País (contiene)": "Country (contains)",
  "Personalizar diseño": "Customize design",
  "Planilla para Excel / Google Sheets.": "Spreadsheet for Excel / Google Sheets.",
  "Por comprar": "To buy",
  "Quitar filtros": "Clear filters",
  "Recargar canciones": "Reload tracks",
  "Recientes": "Recent",
  "Reconoce una canción con el micrófono.": "Identify a song with the microphone.",
  "Reconociendo y buscando…": "Identifying and searching…",
  "Reconocimiento (Escuchar)": "Recognition (Listen)",
  "Reconocimiento por micrófono y carátulas offline.": "Microphone recognition and offline cover OCR.",
  "Reemplaza TODO por el último backup local.": "Replace EVERYTHING with the latest local backup.",
  "Reemplazar todo": "Replace all",
  "Reseña": "Review",
  "Restaurar": "Restore",
  "Selecciona un archivo para fusionar o reemplazar datos.": "Select a file to merge or replace data.",
  "Sin artistas aún": "No artists yet",
  "Sin resultados": "No results",
  "Single": "Single",
  "Solo faltantes": "Missing only",
  "Tema": "Theme",
  "Tema, contraste y bordes.": "Theme, contrast and borders.",
  "Texto": "Text",
  "Texto detectado": "Detected text",
  "Token AudD": "AudD token",
  "Tomar foto": "Take photo",
  "Tu lista de deseos está vacía": "Your wishlist is empty",
  "VG": "VG",
  "VG+": "VG+",
  "Vinilos": "Records",
  "Vista previa": "Preview",
  "Volver": "Back",
  "Ya lo tienes en tu colección:": "Already in your collection:",
  "api_token…": "api_token…",
  "¿Dónde quieres agregarlo?": "Where do you want to add it?",
  "¿Enviar a papelera?": "Move to trash?",
  "Álbum": "Album",
  "Álbum encontrado": "Album found",
  "Idioma": "Language",
  "Español": "Spanish",
  "Inglés": "English",
  "Usar inglés": "Use English",
  "Cambiar idioma entre Español e Inglés.": "Switch between Spanish and English.",
  "Ajustes": "Settings",
  "Escáner": "Scanner",
  "Discografías": "Discographies",
  "Deseos": "Wishlist",
  "Favoritos": "Favorites",
  "General": "General",
  "Backup y exportación": "Backup & export",
  "Escáner y audio": "Scanner & audio",
  "Colección": "Collection",
  "Apariencia": "Appearance",
  "Agregado a Deseos ✅": "Added to wishlist ✅",
  "Agregado a tu lista de vinilos": "Added to your records list",
  "Agregado a wishlist": "Added to wishlist",
  "Agregado a wishlist ✅": "Added to wishlist ✅",
  "Agregado ✅": "Added ✅",
  "Backup guardado ✅": "Backup saved ✅",
  "Configura el token en Ajustes → Reconocimiento (Escuchar).": "Set up the token in Settings → Recognition (Listen).",
  "Eliminado de la lista de deseos": "Removed from wishlist",
  "Error actualizando favorito": "Error updating favorite",
  "Error agregando": "Error adding",
  "Error agregando a wishlist": "Error adding to wishlist",
  "Error cargando discografía": "Error loading discography",
  "Exportación cancelada.": "Export cancelled.",
  "Falta artista o álbum.": "Missing artist or album.",
  "Guardado automático: ACTIVADO ☁️": "Auto backup: ON ☁️",
  "Guardado automático: MANUAL ☁️": "Auto backup: MANUAL ☁️",
  "Importación cancelada.": "Import cancelled.",
  "Lista cargada ✅": "List loaded ✅",
  "Listo ✅": "Done ✅",
  "No hay duplicados ✅": "No duplicates ✅",
  "No pude cargar metadata. Puedes agregar igual.": "Couldn't load metadata. You can still add it.",
  "No pude preparar la info.": "Couldn't prepare the info.",
  "No se pudo agregar": "Couldn't add",
  "No tengo artista y álbum para continuar.": "I don't have artist and album to continue.",
  "Permiso de micrófono denegado.": "Microphone permission denied.",
  "Preparando…": "Preparing…",
  "Primero agrégalo a tu lista": "Add it to your collection first",
  "Ya está en tu lista": "It's already in your collection",
  "Ya está en wishlist": "It's already in your wishlist",
  "Ya existe en Deseos.": "Already in Wishlist.",
  "Token guardado ✅": "Token saved ✅",
  "Reconocimiento desactivado": "Recognition disabled",
  "Ver más": "See more",
  "Ver menos": "See less",
  "Debes usar “Guardar backup” manualmente.": "You must use “Save backup” manually.",
  "Respalda solo cuando agregas o borras vinilos.": "Back up only when you add or delete records.",
  "Tu estantería": "Your shelf",
  "Actualizar": "Refresh",
  "Organiza tu música": "Organize your music",
  "Papelera y limpieza": "Trash & cleanup",
  "Backup y diseño": "Backup & design",
  "Borrar": "Delete",
  "Mostrar precios": "Show prices",
  "Ocultar precios": "Hide prices",
  "Lista": "List",
  "Fav": "Fav",
  "Cargando...": "Loading...",
  "Quitar favorito": "Remove favorite",
  "Marcar favorito": "Mark favorite",
  "No disponible": "Not available",
  "Agregar a deseos": "Add to wishlist",
  "Error cargando wishlist": "Error loading wishlist",
  "No encontré canciones.": "No tracks found.",
  "Error cargando información.": "Error loading information.",
  "Búsqueda": "Search",
  "No se pudo guardar": "Couldn't save",
  "No hay ID (MBID) guardado para este LP, no puedo buscar canciones.": "No MBID saved for this record, I can't load tracks.",
  "No encontré canciones para este disco.": "No tracks found for this record.",
  "GaBoLP — Inventario": "GaBoLP — Inventory",
  "Total": "Total",
  "Cod.": "Code",
  "Cond.": "Cond.",
  "Para reconocer canciones necesitas un token (AudD).\n\nPega tu token aquí. Puedes dejarlo vacío para desactivar.": "To recognize songs you need an AudD token.\n\nPaste your token here. Leave it blank to disable.",
  "Obsidiana": "Obsidian",
  "Marfil": "Ivory",
  "Grafito": "Graphite",
  "Vinilo Retro": "Retro Vinyl",
  "Lila": "Lilac",
  "Verde Sala": "Living Room Green",
  "Suave": "Soft",
  "Normal": "Normal",
  "Fuerte": "Strong",
  "Máx": "Max",
  "Blanco suave": "Soft white",
  "Gris frío": "Cool gray",
  "Gris cálido": "Warm gray",
  "Verde menta": "Mint green",
  "Verde salvia": "Sage green",
  "Rojo rosado": "Rose red",
  "Durazno": "Peach",
  "Bronce": "Bronze",
  "Azul hielo": "Ice blue",
  "copias": "copies",
  "Nivel": "Level",

  "Busca Discografías": "Search Discographies",
  "Primero agrega a tu lista": "Add to your collection first",
  "No se pudo actualizar favorito (0 filas afectadas).": "Could not update favorite (0 rows affected).",
  "Vinilo no encontrado.": "Record not found.",
  "No se pudo persistir favorito.": "Could not save favorite.",
  "Duplicado": "Duplicate",
  "Artista y Álbum son obligatorios.": "Artist and Album are required.",
  "No encontré el vinilo.": "I couldn't find the record.",
  "Ese vinilo ya existe en tu lista.": "That record already exists in your collection.",

  "Últimos agregados": "Latest added",
  "Ver todos": "View all",
  "No hay favoritos": "No favorites",
  "No hay vinilos": "No records",
  "Marca un vinilo como favorito y aparecerá aquí.": "Mark a record as favorite and it will show up here.",
  "Agrega tu primer vinilo desde Discografía o Buscar.": "Add your first record from Discographies or Scan.",
  "Cuando agregues vinilos, aquí verás tu colección agrupada por artista.": "When you add records, you’ll see your collection grouped by artist here.",
  "No encontré artistas que coincidan con tu búsqueda.": "I couldn't find artists matching your search.",
  "No encontré coincidencias en tu lista.": "I couldn't find matches in your collection.",
  "Limpiar búsqueda": "Clear search",
  "Papelera vacía": "Trash is empty",
  "Aquí aparecerán los vinilos que borres para que puedas recuperarlos.": "Deleted records will appear here so you can recover them.",
  "Colección vinilos": "Vinyl collection",
};

  static bool isEnglish(BuildContext context) {
    final code = LocaleService.code;
    return code == 'en';
  }


  static String tRaw(String esText) {
    if (LocaleService.code == 'en') return _en[esText] ?? esText;
    return esText;
  }

  static String t(BuildContext context, String esText) {
    if (isEnglish(context)) {
      return _en[esText] ?? esText;
    }
    return esText;
  }

  // Helpers para frases con variables (evita hardcodear "Año: ..." en ES).
  static String labeled(BuildContext context, String labelEs, String value) {
    return '${t(context, labelEs)}: $value';
  }

  static String tracksCount(BuildContext context, int n) {
    if (isEnglish(context)) return 'Tracks ($n)';
    return 'Canciones ($n)';
  }

  static String resultsCountForCode(BuildContext context, int n, String code) {
    if (isEnglish(context)) return 'Results ($n) — $code';
    return 'Resultados ($n) — $code';
  }

  static String viewModeHint(BuildContext context, String current, String next) {
    if (isEnglish(context)) return 'View: $current · tap to $next';
    return 'Vista: $current · tocar para $next';
  }

  static String shownOfTotal(BuildContext context, int shown, int total) {
    if (isEnglish(context)) return '$shown of $total';
    return '$shown de $total';
  }
}

extension AppStringsX on BuildContext {
  /// Traduce un texto ES a EN (si el usuario eligió Inglés).
  String tr(String esText) => AppStrings.t(this, esText);

  /// Traducción ‘inteligente’ para mensajes que incluyen detalles (errores, rutas, etc).
  /// Intenta traducir el texto completo; si no existe, traduce el prefijo antes de ‘: ’
  /// o la primera línea (antes de \n) y deja el resto intacto.
  String trSmart(String text) {
    final exact = AppStrings.t(this, text);
    if (exact != text) return exact;

    final idx = text.indexOf(': ');
    if (idx > 0) {
      final head = text.substring(0, idx);
      final tail = text.substring(idx);
      final headT = AppStrings.t(this, head);
      if (headT != head) return headT + tail;
    }

    final nl = text.indexOf('\n');
    if (nl > 0) {
      final head = text.substring(0, nl);
      final tail = text.substring(nl);
      final headT = AppStrings.t(this, head);
      if (headT != head) return headT + tail;
    }

    return text;
  }
}
