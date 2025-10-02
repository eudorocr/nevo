
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
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF6D4AFF)), useMaterial3: true),
      home: const EventListPage(),
    );
  }
}

class Event {final String id,titulo; final String? descripcion; final DateTime fecha;
  Event({required this.id,required this.titulo,this.descripcion,required this.fecha});
  factory Event.newEvent(){final n=DateTime.now();final d=DateTime(n.year,n.month,n.day);return Event(id: DateTime.now().microsecondsSinceEpoch.toString(),titulo:'',descripcion:null,fecha:d);}
  Map<String,dynamic> toJson()=>{'id':id,'titulo':titulo,'descripcion':descripcion,'fecha':fecha.toIso8601String()};
  factory Event.fromJson(Map<String,dynamic> m)=>Event(id:m['id'],titulo:(m['titulo']??''),descripcion:m['descripcion'],fecha:DateTime.parse(m['fecha']));
}
class EventStore{
  static const _k='events';
  Future<List<Event>> load() async {final p=await SharedPreferences.getInstance();final raw=p.getStringList(_k)??[];return raw.map((s)=>Event.fromJson(json.decode(s))).toList();}
  Future<void> save(List<Event> evs) async {final p=await SharedPreferences.getInstance();await p.setStringList(_k, evs.map((e)=>json.encode(e.toJson())).toList());}
}
class CalendarImporter{
  final dc.DeviceCalendarPlugin _p=dc.DeviceCalendarPlugin();
  Future<bool> _perm() async {final h=await _p.hasPermissions(); if(h?.data==true) return true; final r=await _p.requestPermissions(); return r?.data==true;}
  Future<List<dc.Calendar>> listCalendars() async {if(!await _perm()) throw 'Permiso denegado'; return (await _p.retrieveCalendars()).data?.toList()??[];}
  Future<List<Event>> importFor(String id, DateTime a, DateTime b) async {
    if(!await _perm()) throw 'Permiso denegado'; final res=await _p.retrieveEvents(id, dc.RetrieveEventsParams(startDate:a,endDate:b));
    final out=<Event>[]; for(final e in (res.data??[])){final dt=(e.start?.toLocal())??DateTime.now();final d=DateTime(dt.year,dt.month,dt.day);
      final idu=e.eventId??dt.millisecondsSinceEpoch.toString(); out.add(Event(id:'ext:$id:$idu:${d.toIso8601String()}',titulo:(e.title??'(sin título)').trim(),descripcion:(e.description?.trim().isEmpty??true)?null:e.description!.trim(),fecha:d));}
    return out;
  }
}
class EventListPage extends StatefulWidget{const EventListPage({super.key}); @override State<EventListPage> createState()=>_S();}
class _S extends State<EventListPage>{
  final _store=EventStore(); final _imp=CalendarImporter(); final _events=<Event>[]; bool _loading=true;
  @override void initState(){super.initState(); _load();}
  Future<void> _load() async {final evs=await _store.load(); evs.sort((a,b)=>a.fecha.compareTo(b.fecha)); setState((){_events..clear()..addAll(evs); _loading=false;});}
  Future<void> _persist()=>_store.save(_events);
  Future<void> _import() async {
    setState(()=>_loading=true);
    try{
      final cals=await _imp.listCalendars();
      if(!mounted) return;
      final p=await showModalBottomSheet<_ImportParams>(context: context, isScrollControlled:true, builder: (_)=>ImportSheetMulti(calendars:cals));
      if(p==null) return;
      int added=0;
      for(final id in p.ids){ final items=await _imp.importFor(id, p.start, p.end);
        for(final ev in items){final exists=_events.any((x)=>x.titulo==ev.titulo && x.fecha.year==ev.fecha.year && x.fecha.month==ev.fecha.month && x.fecha.day==ev.fecha.day);
          if(!exists){_events.add(ev); added++;}}}
      _events.sort((a,b)=>a.fecha.compareTo(b.fecha)); await _persist();
      if(!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Importados $added evento(s)')));
    }catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));} finally {if(mounted) setState(()=>_loading=false);}
  }
  @override Widget build(BuildContext c){ return Scaffold(appBar: AppBar(title: const Text('Eventos por fecha'), actions:[IconButton(onPressed:_import, icon: const Icon(Icons.download))]),
      body: _loading? const Center(child:CircularProgressIndicator()): ListView.builder(itemCount:_events.length,itemBuilder:(_,i){final e=_events[i]; return ListTile(title: Text(e.titulo), subtitle: Text(e.fecha.toIso8601String().split('T').first));}));
  }
}
class _ImportParams{final List<String> ids; final DateTime start,end; const _ImportParams(this.ids,this.start,this.end);}
class ImportSheetMulti extends StatefulWidget{final List<dc.Calendar> calendars; const ImportSheetMulti({super.key,required this.calendars}); @override State<ImportSheetMulti> createState()=>_IS();}
class _IS extends State<ImportSheetMulti>{
  late Map<String,bool> _sel; late DateTime _a,_b; late TextEditingController _ac,_bc;
  @override void initState(){super.initState(); _sel={for(final c in widget.calendars)(c.id??''): !(c.isReadOnly??false)}; if(_sel.values.every((v)=>!v)&&_sel.isNotEmpty) _sel[_sel.keys.first]=true;
    final now=DateTime.now(); _a=DateTime(now.year,now.month,now.day).subtract(const Duration(days:30)); _b=DateTime(now.year,now.month,now.day).add(const Duration(days:90));
    _ac=TextEditingController(text:_fmt(_a)); _bc=TextEditingController(text:_fmt(_b));}
  @override void dispose(){_ac.dispose(); _bc.dispose(); super.dispose();}
  String _fmt(DateTime d){return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';}
  DateTime? _parse(String s){final t=s.trim(); final a=RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(t); if(a!=null){final d=int.tryParse(a.group(1)!); final m=int.tryParse(a.group(2)!); final y=int.tryParse(a.group(3)!); if(d!=null&&m!=null&&y!=null){return DateTime(y,m,d);}}
    final b=RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$').firstMatch(t); if(b!=null){final y=int.tryParse(b.group(1)!); final m=int.tryParse(b.group(2)!); final d=int.tryParse(b.group(3)!); if(d!=null&&m!=null&&y!=null){return DateTime(y,m,d);}}
    return null;}
  Future<void> _alert(String msg) async {await showDialog(context: context, builder: (_)=> AlertDialog(title: const Text('No se puede importar'), content: Text(msg), actions:[TextButton(onPressed: ()=>Navigator.of(context, rootNavigator:true).pop(), child: const Text('OK'))]));}
  @override Widget build(BuildContext c){
    final idsSel=_sel.entries.where((e)=>e.value).map((e)=>e.key).toList(); final countSel=idsSel.length;
    return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: SafeArea(child:
      Padding(padding: const EdgeInsets.fromLTRB(16,16,16,12), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children:[
        Center(child: Container(width:32,height:4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(3)))),
        const SizedBox(height:12),
        Text('Importar de calendarios', style: Theme.of(c).textTheme.titleLarge),
        const SizedBox(height:8),
        Row(children:[Expanded(child: Text('Selecciona uno o varios ($countSel)')), TextButton.icon(onPressed: (){final all=_sel.values.every((v)=>v); setState((){for(final k in _sel.keys){_sel[k]=!all;}});}, icon: const Icon(Icons.select_all), label: const Text('Todos/Ninguno'))]),
        const SizedBox(height:8),
        ConstrainedBox(constraints: const BoxConstraints(maxHeight: 240), child: Scrollbar(child: ListView.builder(shrinkWrap:true, itemCount: widget.calendars.length, itemBuilder: (_,i){
          final cal=widget.calendars[i]; final id=cal.id??''; final name=(cal.name??'Sin nombre'); final ro=(cal.isReadOnly??false)?' · sólo lectura':'';
          return CheckboxListTile(value: _sel[id]??false, onChanged: (v)=> setState(()=> _sel[id]=v??false), title: Text(name), subtitle: Text('ID: '+(id.isEmpty?'(sin ID)':id)+ro, maxLines:1, overflow: TextOverflow.ellipsis));}))),
        const SizedBox(height:12),
        Row(children:[Expanded(child: TextField(controller:_ac, decoration: const InputDecoration(labelText:'Inicio', prefixIcon: Icon(Icons.event)), keyboardType: TextInputType.datetime, onSubmitted: (_){final p=_parse(_ac.text); if(p!=null) setState(()=>_a=p);})), const SizedBox(width:8), IconButton(onPressed: () async {final p=await showDatePicker(context:c, initialDate:_a, firstDate:DateTime(1900), lastDate:DateTime(2100)); if(p!=null) setState(()=>{_a=DateTime(p.year,p.month,p.day), _ac.text=_fmt(_a)});}, icon: const Icon(Icons.calendar_month))]),
        const SizedBox(height:8),
        Row(children:[Expanded(child: TextField(controller:_bc, decoration: const InputDecoration(labelText:'Fin', prefixIcon: Icon(Icons.event)), keyboardType: TextInputType.datetime, onSubmitted: (_){final p=_parse(_bc.text); if(p!=null) setState(()=>_b=p);})), const SizedBox(width:8), IconButton(onPressed: () async {final p=await showDatePicker(context:c, initialDate:_b, firstDate:DateTime(1900), lastDate:DateTime(2100)); if(p!=null){setState(()=>{_b=DateTime(p.year,p.month,p.day)}); _bc.text=_fmt(_b);}}, icon: const Icon(Icons.calendar_month))]),
        const SizedBox(height:12),
        Row(mainAxisAlignment: MainAxisAlignment.end, children:[
          TextButton(onPressed: ()=>Navigator.of(c).pop(), child: const Text('Cancelar')),
          const SizedBox(width:12),
          FilledButton.icon(onPressed: () async {
            final all = _sel.entries.where((e)=>e.value).map((e)=>e.key).toList();
            if(all.isEmpty){ await _alert('Selecciona al menos un calendario.'); return; }
            final ids = all.where((k)=>k.isNotEmpty).toList();
            if(ids.isEmpty){ await _alert('Los calendarios seleccionados no tienen un ID válido.'); return; }
            if(_b.isBefore(_a)){ await _alert('El fin no puede ser anterior al inicio.'); return; }
            Navigator.of(c).pop(_ImportParams(ids, _a, _b));
          }, icon: const Icon(Icons.download), label: const Text('Importar')),
        ])
      ]))));
  }
}
