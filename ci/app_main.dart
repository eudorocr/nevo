import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:device_calendar/device_calendar.dart' as dc;

void main() => runApp(const EventosApp());

class EventosApp extends StatelessWidget {
  const EventosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Eventos',
      locale: const Locale('es'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es'), Locale('en')],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF6D4AFF)),
        useMaterial3: true,
      ),
      home: const EventListPage(),
    );
  }
}

class Event {
  final String id;
  final String titulo;
  final String? descripcion;
  final DateTime fecha;

  Event({required this.id, required this.titulo, this.descripcion, required this.fecha});

  factory Event.newEvent() {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day);
    return Event(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      titulo: '',
      descripcion: null,
      fecha: d,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'titulo': titulo,
    'descripcion': descripcion,
    'fecha': fecha.toIso8601String(),
  };

  factory Event.fromJson(Map<String, dynamic> m) => Event(
    id: m['id'] as String,
    titulo: (m['titulo'] as String?) ?? '',
    descripcion: m['descripcion'] as String?,
    fecha: DateTime.parse(m['fecha'] as String),
  );
}

class EventStore {
  static const _key = 'events';
  Future<List<Event>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    return raw.map((s) => Event.fromJson(json.decode(s) as Map<String, dynamic>)).toList();
  }

  Future<void> save(List<Event> events) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = events.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList(_key, raw);
  }
}

class CalendarImporter {
  final dc.DeviceCalendarPlugin _plugin = dc.DeviceCalendarPlugin();

  Future<bool> _ensurePermissions() async {
    final res = await _plugin.hasPermissions();
    if (res?.data == true) return true;
    final req = await _plugin.requestPermissions();
    return req?.data == true;
  }

  Future<List<Event>> importEvents({
    DateTime? start,
    DateTime? end,
    int maxEvents = 500,
  }) async {
    final ok = await _ensurePermissions();
    if (!ok) throw 'Permiso de calendario denegado';

    start ??= DateTime.now().subtract(const Duration(days: 365));
    end   ??= DateTime.now().add(const Duration(days: 365));

    final List<dc.Calendar> cals =
        (await _plugin.retrieveCalendars()).data?.toList() ?? <dc.Calendar>[];
    if (cals.isEmpty) return [];

    final dc.Calendar cal = cals.firstWhere(
      (c) => (c.isReadOnly ?? false) == false,
      orElse: () => cals.first,
    );
    if (cal.id == null || cal.id!.isEmpty) return [];

    final evRes = await _plugin.retrieveEvents(
      cal.id!,
      dc.RetrieveEventsParams(startDate: start, endDate: end),
    );

    final List<dc.Event> evs = evRes.data?.toList() ?? <dc.Event>[];
    final out = <Event>[];

    for (final e in evs) {
      final dt = (e.start?.toLocal()) ?? DateTime.now();
      final d  = DateTime(dt.year, dt.month, dt.day);
      final title = (e.title == null || e.title!.trim().isEmpty)
          ? '(sin título)'
          : e.title!.trim();
      final descr = (e.description?.trim().isEmpty ?? true)
          ? null
          : e.description!.trim();
      final unique = e.eventId ?? dt.millisecondsSinceEpoch.toString();
      final id = 'ext:${cal.id}:$unique:${d.toIso8601String()}';
      out.add(Event(id: id, titulo: title, descripcion: descr, fecha: d));
      if (out.length >= maxEvents) break;
    }
    return out;
  }
}

class EventActionResult {
  final Event? event;
  final bool deleted;
  const EventActionResult._(this.event, this.deleted);
  factory EventActionResult.saved(Event e) => EventActionResult._(e, false);
  factory EventActionResult.deleted()     => const EventActionResult._(null, true);
}

class EventListPage extends StatefulWidget {
  const EventListPage({super.key});
  @override
  State<EventListPage> createState() => _EventListPageState();
}

class _EventListPageState extends State<EventListPage> {
  final _store = EventStore();
  final _importer = CalendarImporter();
  final List<Event> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _store.load();
    items.sort((a, b) => a.fecha.compareTo(b.fecha));
    setState(() {
      _events
        ..clear()
        ..addAll(items);
      _loading = false;
    });
  }

  Future<void> _persist() => _store.save(_events);

  Future<void> _importFromCalendar() async {
    setState(() => _loading = true);
    try {
      final imported = await _importer.importEvents();
      int added = 0;
      for (final ev in imported) {
        final exists = _events.any((x) =>
            x.titulo == ev.titulo &&
            x.fecha.year  == ev.fecha.year &&
            x.fecha.month == ev.fecha.month &&
            x.fecha.day   == ev.fecha.day);
        if (!exists) {
          _events.add(ev);
          added++;
        }
      }
      _events.sort((a, b) => a.fecha.compareTo(b.fecha));
      await _persist();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Importados $added evento(s)')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo importar: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addEvent() async {
    final result = await showDialog<EventActionResult>(
      context: context,
      builder: (ctx) => EventEditorDialog(event: Event.newEvent()),
    );
    if (result?.event != null) {
      setState(() {
        _events.add(result!.event!);
        _events.sort((a, b) => a.fecha.compareTo(b.fecha));
      });
      await _persist();
    }
  }

  void _editEvent(Event e) async {
    final result = await showDialog<EventActionResult>(
      context: context,
      builder: (ctx) => EventEditorDialog(event: e),
    );
    if (result == null) return;
    if (result.deleted) {
      setState(() => _events.removeWhere((x) => x.id == e.id));
      await _persist();
    } else if (result.event != null) {
      final idx = _events.indexWhere((x) => x.id == e.id);
      if (idx != -1) {
        setState(() => _events[idx] = result.event!);
        _events.sort((a, b) => a.fecha.compareTo(b.fecha));
        await _persist();
      }
    }
  }

  // ---- búsqueda por fecha cercana ----
  void _openSearch() async {
    final params = await showModalBottomSheet<SearchParams>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SearchSheet(initial: SearchParams.near(DateTime.now())),
    );
    if (params == null) return;

    final results = _searchAround(params);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchResultsPage(params: params, results: results),
    ));
  }

  List<Event> _searchAround(SearchParams p) {
    bool containsIgnoreCase(String hay, String needle) =>
        hay.toLowerCase().contains(needle.toLowerCase());

    final from = DateTime(p.ref.year, p.ref.month, p.ref.day)
        .subtract(Duration(days: p.rangeDays));
    final to   = DateTime(p.ref.year, p.ref.month, p.ref.day)
        .add(Duration(days: p.rangeDays));

    final filtered = _events.where((e) {
      final inRange = (e.fecha.isAtSameMomentAs(from) || e.fecha.isAfter(from)) &&
                      (e.fecha.isAtSameMomentAs(to)   || e.fecha.isBefore(to));
      final okText = (p.query == null || p.query!.trim().isEmpty)
          ? true
          : (containsIgnoreCase(e.titulo, p.query!.trim()) ||
             (e.descripcion != null && containsIgnoreCase(e.descripcion!, p.query!.trim())));
      return inRange && okText;
    }).toList();

    filtered.sort((a, b) {
      final da = (a.fecha.difference(p.ref).inDays).abs();
      final db = (b.fecha.difference(p.ref).inDays).abs();
      if (da != db) return da.compareTo(db);
      return a.fecha.compareTo(b.fecha);
    });
    return filtered;
  }

  String _formatDate(DateTime d) {
    const meses = [
      'ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'
    ];
    return '${d.day.toString().padLeft(2,'0')} ${meses[d.month-1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eventos por fecha'),
        actions: [
          IconButton(onPressed: _importFromCalendar, icon: const Icon(Icons.download)),
          IconButton(onPressed: _openSearch, icon: const Icon(Icons.search)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96, top: 12),
                  itemCount: _events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = _events[i];
                    return ListTile(
                      title: Text(e.titulo),
                      subtitle: Text(_formatDate(e.fecha)),
                      onTap: () => _editEvent(e),
                    );
                  },
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.event, size: 96, color: Colors.black54),
          SizedBox(height: 16),
          Text('No hay eventos aún.', style: TextStyle(fontSize: 18)),
          SizedBox(height: 4),
          Text('Pulsa el botón + para agregar tu primer evento'),
        ],
      ),
    );
  }
}

// ======= Búsqueda =======

class SearchParams {
  final DateTime ref;
  final int rangeDays;
  final String? query;
  const SearchParams({required this.ref, required this.rangeDays, this.query});
  factory SearchParams.near(DateTime ref, {int rangeDays = 7, String? query}) =>
      SearchParams(ref: DateTime(ref.year, ref.month, ref.day), rangeDays: rangeDays, query: query);
}

class SearchSheet extends StatefulWidget {
  final SearchParams initial;
  const SearchSheet({super.key, required this.initial});

  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  late DateTime _ref;
  late TextEditingController _dateCtrl;
  late TextEditingController _queryCtrl;
  int _range = 7;

  @override
  void initState() {
    super.initState();
    _ref = widget.initial.ref;
    _range = widget.initial.rangeDays;
    _dateCtrl = TextEditingController(text: _formatInputDate(_ref));
    _queryCtrl = TextEditingController(text: widget.initial.query ?? '');
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  String _formatInputDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  DateTime? _parse(String s) {
    final t = s.trim();
    final dmY = RegExp(r'^(\\d{1,2})[/-](\\d{1,2})[/-](\\d{4})$');
    final yMd = RegExp(r'^(\\d{4})[/-](\\d{1,2})[/-](\\d{1,2})$');
    final a = dmY.firstMatch(t);
    if (a != null) {
      final d = int.tryParse(a.group(1)!);
      final m = int.tryParse(a.group(2)!);
      final y = int.tryParse(a.group(3)!);
      if (d != null && m != null && y != null) {
        try { return DateTime(y, m, d); } catch (_) {}
      }
    }
    final b = yMd.firstMatch(t);
    if (b != null) {
      final y = int.tryParse(b.group(1)!);
      final m = int.tryParse(b.group(2)!);
      final d = int.tryParse(b.group(3)!);
      if (d != null && m != null && y != null) {
        try { return DateTime(y, m, d); } catch (_) {}
      }
    }
    return null;
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _ref,
      firstDate: DateTime(1900),
      lastDate:  DateTime(2100),
      helpText: 'Selecciona fecha',
      useRootNavigator: true,
    );
    if (picked != null) {
      setState(() {
        _ref = DateTime(picked.year, picked.month, picked.day);
        _dateCtrl.text = _formatInputDate(_ref);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 32, height: 4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 12),
              Text('Buscar eventos cercanos', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Fecha (dd/mm/aaaa o yyyy-mm-dd)',
                        prefixIcon: Icon(Icons.event),
                      ),
                      keyboardType: TextInputType.datetime,
                      onSubmitted: (_) {
                        final p = _parse(_dateCtrl.text);
                        if (p != null) setState(() => _ref = p);
                      },
                      onEditingComplete: () {
                        final p = _parse(_dateCtrl.text);
                        if (p != null) setState(() => _ref = p);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(onPressed: _pick, icon: const Icon(Icons.calendar_month)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('± días:'),
                  Expanded(
                    child: Slider(
                      value: _range.toDouble(),
                      min: 1,
                      max: 60,
                      divisions: 59,
                      label: '$_range',
                      onChanged: (v) => setState(() => _range = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text('$_range', textAlign: TextAlign.center),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _queryCtrl,
                decoration: const InputDecoration(
                  labelText: 'Contiene texto (opcional)',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () {
                      final p = _parse(_dateCtrl.text);
                      final eff = p ?? _ref;
                      Navigator.of(context).pop(SearchParams(ref: eff, rangeDays: _range, query: _queryCtrl.text.trim().isEmpty ? null : _queryCtrl.text.trim()));
                    },
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchResultsPage extends StatelessWidget {
  final SearchParams params;
  final List<Event> results;
  const SearchResultsPage({super.key, required this.params, required this.results});

  String _formatDate(DateTime d) {
    const meses = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
    return '${d.day.toString().padLeft(2,'0')} ${meses[d.month-1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resultados')),
      body: results.isEmpty
        ? const Center(child: Text('No hay eventos en ese rango.'))
        : ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final e = results[i];
              final delta = e.fecha.difference(params.ref).inDays;
              final sgn = delta == 0 ? 'hoy' : (delta > 0 ? '+$delta días' : '${delta} días');
              return ListTile(
                title: Text(e.titulo),
                subtitle: Text('${_formatDate(e.fecha)}  ·  $sgn'),
              );
            },
          ),
    );
  }
}
