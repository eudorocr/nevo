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
    final res = await _plugin.hasPermissions(); // Result<bool>
    if (res?.data == true) return true;
    final req = await _plugin.requestPermissions(); // Result<bool>
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

class EventEditorDialog extends StatefulWidget {
  final Event event;
  const EventEditorDialog({super.key, required this.event});

  @override
  State<EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<EventEditorDialog> {
  late TextEditingController _title;
  late TextEditingController _desc;
  late DateTime _fecha;
  late TextEditingController _dateCtrl;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.event.titulo);
    _desc  = TextEditingController(text: widget.event.descripcion ?? '');
    _fecha = widget.event.fecha;
    _dateCtrl = TextEditingController(text: _formatInputDate(_fecha));
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  String _formatInputDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  DateTime? _tryParseInputDate(String s) {
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(1900),
      lastDate:  DateTime(2100),
      helpText: 'Selecciona fecha',
      useRootNavigator: true,
    );
    if (picked != null) {
      setState(() {
        _fecha = DateTime(picked.year, picked.month, picked.day);
        _dateCtrl.text = _formatInputDate(_fecha);
      });
    }
  }

  void _save() {
    final t = _title.text.trim();
    if (t.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un título'))
      );
      return;
    }
    final parsed = _tryParseInputDate(_dateCtrl.text);
    final eff = parsed ?? _fecha;
    final updated = Event(
      id: widget.event.id,
      titulo: t,
      descripcion: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      fecha: DateTime(eff.year, eff.month, eff.day),
    );
    Navigator.of(context, rootNavigator: true).pop(EventActionResult.saved(updated));
  }

  void _delete() {
    Navigator.of(context, rootNavigator: true).pop(EventActionResult.deleted());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.event.titulo.isEmpty ? 'Nuevo evento' : 'Editar evento',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  prefixIcon: Icon(Icons.title),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 16),
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
                        final p = _tryParseInputDate(_dateCtrl.text);
                        if (p != null) setState(() => _fecha = p);
                      },
                      onEditingComplete: () {
                        final p = _tryParseInputDate(_dateCtrl.text);
                        if (p != null) setState(() => _fecha = p);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month),
                    tooltip: 'Cambiar',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(onPressed: () => Navigator.of(context, rootNavigator: true).pop(), child: const Text('Cancelar')),
                  FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Guardar')),
                ],
              ),
              if (widget.event.titulo.isNotEmpty) ...[
                const Divider(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
