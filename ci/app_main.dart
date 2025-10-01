import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EventosApp());
}

class EventosApp extends StatelessWidget {
  const EventosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eventos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const EventListPage(),
    );
  }
}

class Event {
  final String id; // uuid-ish
  String titulo;
  String? descripcion;
  DateTime fecha;

  Event({
    required this.id,
    required this.titulo,
    required this.fecha,
    this.descripcion,
  });

  factory Event.newEvent() => Event(
        id: UniqueKey().toString(),
        titulo: '',
        fecha: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'descripcion': descripcion,
        'fecha': fecha.toIso8601String(),
      };

  factory Event.fromJson(Map<String, dynamic> j) => Event(
        id: j['id'] as String,
        titulo: j['titulo'] as String,
        descripcion: j['descripcion'] as String?,
        fecha: DateTime.parse(j['fecha'] as String),
      );
}

class EventStore {
  static const _key = 'events_v1';

  Future<List<Event>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List)
        .map((e) => Event.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => a.fecha.compareTo(b.fecha));
    return list;
  }

  Future<void> save(List<Event> events) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = events.map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(jsonList));
  }
}

class EventListPage extends StatefulWidget {
  const EventListPage({super.key});

  @override
  State<EventListPage> createState() => _EventListPageState();
}

class _EventListPageState extends State<EventListPage> {
  final _store = EventStore();
  List<Event> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _store.load();
    setState(() {
      _events = data;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    await _store.save(_events);
    setState(() {});
  }

  void _addEvent() async {
    final created = await showDialog<Event>(
      context: context,
      builder: (ctx) => EventEditorDialog(event: Event.newEvent()),
    );
    if (created != null) {
      _events.add(created);
      _events.sort((a, b) => a.fecha.compareTo(b.fecha));
      await _persist();
    }
  }

  void _editEvent(Event e) async {
    final updated = await showDialog<EventActionResult>(
      context: context,
      builder: (ctx) => EventEditorDialog(event: Event(
        id: e.id,
        titulo: e.titulo,
        descripcion: e.descripcion,
        fecha: e.fecha,
      )),
    );

    if (updated == null) return;

    if (updated.deleted) {
      _events.removeWhere((el) => el.id == e.id);
    } else if (updated.event != null) {
      final idx = _events.indexWhere((el) => el.id == e.id);
      if (idx != -1) _events[idx] = updated.event!;
      _events.sort((a, b) => a.fecha.compareTo(b.fecha));
    }
    await _persist();
  }

  void _openSearch() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchNearbyPage(all: _events),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eventos por fecha'),
        actions: [
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
              : ListView.builder(
                  itemCount: _events.length,
                  itemBuilder: (context, i) => _EventTile(
                    event: _events[i],
                    onTap: () => _editEvent(_events[i]),
                  ),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.event_note, size: 72),
          const SizedBox(height: 12),
          const Text('No hay eventos aún.'),
          const SizedBox(height: 4),
          Text(
            'Pulsa el botón + para agregar tu primer evento',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;
  const _EventTile({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fechaFmt = _formatDate(event.fecha);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.event),
        title: Text(event.titulo.isEmpty ? '(Sin título)' : event.titulo),
        subtitle: Text('${event.descripcion?.trim().isEmpty ?? true ? '' : event.descripcion!.trim() + '\n'}$fechaFmt'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  final months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
}

class EventActionResult {
  final Event? event;
  final bool deleted;
  EventActionResult.saved(this.event) : deleted = false;
  EventActionResult.deleted()
      : event = null,
        deleted = true;
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

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.event.titulo);
    _desc = TextEditingController(text: widget.event.descripcion ?? '');
    _fecha = widget.event.fecha;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      locale: const Locale('es'),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  void _save() {
    if (_title.text.trim().isEmpty && _desc.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese al menos un título o descripción')),
      );
      return;
    }
    final updated = Event(
      id: widget.event.id,
      titulo: _title.text.trim(),
      descripcion: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      fecha: DateTime(_fecha.year, _fecha.month, _fecha.day),
    );
    Navigator.of(context).pop(EventActionResult.saved(updated));
  }

  void _delete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar evento'),
        content: const Text('¿Desea eliminar este evento?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pop(EventActionResult.deleted());
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.event.titulo.isEmpty ? 'Nuevo evento' : 'Editar evento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Título',
                prefixIcon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('Fecha: ${_formatDate(_fecha)}'),
                ),
                TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Cambiar'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (widget.event.titulo.isNotEmpty || (widget.event.descripcion?.isNotEmpty ?? false))
          TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}

class SearchNearbyPage extends StatefulWidget {
  final List<Event> all;
  const SearchNearbyPage({super.key, required this.all});

  @override
  State<SearchNearbyPage> createState() => _SearchNearbyPageState();
}

class _SearchNearbyPageState extends State<SearchNearbyPage> {
  DateTime _target = DateTime.now();
  double _windowDays = 7; // +/- days

  List<Event> get _results {
    final start = _target.subtract(Duration(days: _windowDays.round()));
    final end = _target.add(Duration(days: _windowDays.round()));
    final filtered = widget.all.where((e) => !e.fecha.isBefore(start) && !e.fecha.isAfter(end)).toList();
    filtered.sort((a, b) {
      final da = (a.fecha.difference(_target).inDays).abs();
      final db = (b.fecha.difference(_target).inDays).abs();
      final cmp = da.compareTo(db);
      return cmp != 0 ? cmp : a.fecha.compareTo(b.fecha);
    });
    return filtered;
  }

  Future<void> _pickTarget() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _target,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      locale: const Locale('es'),
    );
    if (picked != null) setState(() => _target = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar cercanos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Fecha objetivo: ${_formatDate(_target)}')),
                    TextButton.icon(
                      onPressed: _pickTarget,
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('Elegir fecha'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Rango: ±${_windowDays.round()} días'),
                Slider(
                  min: 0,
                  max: 60,
                  divisions: 60,
                  value: _windowDays,
                  label: '±${_windowDays.round()} días',
                  onChanged: (v) => setState(() => _windowDays = v),
                ),
              ],
            ),
          ),
          const Divider(height: 0),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('Sin eventos en el rango'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) => _EventTile(event: _results[i], onTap: () {}),
                  ),
          ),
        ],
      ),
    );
  }
}
