import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Semua waktu disimpan di database sebagai timestamptz (UTC) dan ditampilkan
// dalam WIB (UTC+7), sehingga hasilnya sama di browser mana pun.
const Duration _wib = Duration(hours: 7);

const List<Color> _roomColors = [
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFFB8C00),
  Color(0xFF8E24AA),
  Color(0xFFE53935),
  Color(0xFF00897B),
];

const List<String> _namaBulan = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];
const List<String> _namaHari = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

/// "Waktu dinding" WIB dipakai sebagai DateTime UTC supaya perbandingan konsisten.
DateTime _toWib(DateTime d) => d.toUtc().add(_wib);
DateTime _fromWib(DateTime w) =>
    DateTime.utc(w.year, w.month, w.day, w.hour, w.minute).subtract(_wib);
String _hm(DateTime w) =>
    '${w.hour.toString().padLeft(2, '0')}:${w.minute.toString().padLeft(2, '0')}';
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _Room {
  final dynamic id;
  final String name;
  final int? capacity;
  final String facilities;
  _Room.fromMap(Map<String, dynamic> m)
      : id = m['id'],
        name = (m['name'] ?? '').toString(),
        capacity = m['capacity'] is int ? m['capacity'] as int : null,
        facilities = (m['facilities'] ?? '').toString();
}

class _Booking {
  final dynamic id;
  final dynamic roomId;
  final String title;
  final String pic;
  final String notes;
  final String? createdBy;
  final DateTime start; // WIB
  final DateTime end; // WIB
  _Booking.fromMap(Map<String, dynamic> m)
      : id = m['id'],
        createdBy = m['created_by']?.toString(),
        roomId = m['room_id'],
        title = (m['title'] ?? '').toString(),
        pic = (m['pic_name'] ?? '').toString(),
        notes = (m['notes'] ?? '').toString(),
        start = _toWib(DateTime.parse(m['start_at'].toString())),
        end = _toWib(DateTime.parse(m['end_at'].toString()));
}

class WebRuangMeetingPage extends StatefulWidget {
  /// true = admin (boleh ubah/batalkan semua booking).
  /// false = user biasa (boleh booking, serta ubah/batalkan booking miliknya sendiri).
  final bool isAdmin;
  const WebRuangMeetingPage({super.key, this.isAdmin = false});

  @override
  State<WebRuangMeetingPage> createState() => _WebRuangMeetingPageState();
}

class _WebRuangMeetingPageState extends State<WebRuangMeetingPage> {
  bool _loading = true;
  String? _error;
  List<_Room> _rooms = [];
  List<_Booking> _bookings = [];
  List<_Booking> _todayBookings = [];
  late DateTime _month;
  late DateTime _selectedDay;
  dynamic _roomFilter; // null = semua ruang
  String _myName = '';

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  /// Admin boleh mengelola semua booking; user biasa hanya miliknya sendiri.
  bool _canManage(_Booking b) =>
      widget.isAdmin || (_uid != null && b.createdBy == _uid);

  Future<void> _loadMyName() async {
    try {
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email == null) return;
      final row = await Supabase.instance.client
          .from('employees')
          .select('full_name')
          .eq('email', email)
          .maybeSingle();
      if (row != null && mounted) {
        _myName = (row['full_name'] ?? '').toString();
      }
    } catch (_) {
      // Abaikan: PIC tinggal diisi manual.
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMyName();
    final now = _toWib(DateTime.now());
    _month = DateTime.utc(now.year, now.month, 1);
    _selectedDay = DateTime.utc(now.year, now.month, now.day);
    _load();
  }

  Color _roomColor(dynamic roomId) {
    final idx = _rooms.indexWhere((r) => r.id.toString() == roomId.toString());
    return _roomColors[(idx < 0 ? 0 : idx) % _roomColors.length];
  }

  _Room? _roomById(dynamic id) {
    for (final r in _rooms) {
      if (r.id.toString() == id.toString()) return r;
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;

      final roomRows = await client
          .from('meeting_rooms')
          .select()
          .eq('is_active', true)
          .order('sort_order');

      final mStart = _fromWib(DateTime.utc(_month.year, _month.month, 1));
      final mEnd = _fromWib(DateTime.utc(_month.year, _month.month + 1, 1));
      final monthRows = await client
          .from('meeting_bookings')
          .select()
          .eq('status', 'active')
          .lt('start_at', mEnd.toIso8601String())
          .gt('end_at', mStart.toIso8601String())
          .order('start_at');

      final now = _toWib(DateTime.now());
      final tStart = _fromWib(DateTime.utc(now.year, now.month, now.day));
      final tEnd = tStart.add(const Duration(days: 1));
      final todayRows = await client
          .from('meeting_bookings')
          .select()
          .eq('status', 'active')
          .lt('start_at', tEnd.toIso8601String())
          .gt('end_at', tStart.toIso8601String())
          .order('start_at');

      if (!mounted) return;
      setState(() {
        _rooms = (roomRows as List)
            .map((e) => _Room.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        _bookings = (monthRows as List)
            .map((e) => _Booking.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        _todayBookings = (todayRows as List)
            .map((e) => _Booking.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat data ruang meeting: $e';
        _loading = false;
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime.utc(_month.year, _month.month + delta, 1);
      _selectedDay = _month;
    });
    _load();
  }

  void _goToday() {
    final now = _toWib(DateTime.now());
    setState(() {
      _month = DateTime.utc(now.year, now.month, 1);
      _selectedDay = DateTime.utc(now.year, now.month, now.day);
    });
    _load();
  }

  List<_Booking> _forDay(List<_Booking> list, DateTime day,
      {bool useFilter = true}) {
    final ds = DateTime.utc(day.year, day.month, day.day);
    final de = ds.add(const Duration(days: 1));
    return list.where((b) {
      if (!(b.start.isBefore(de) && b.end.isAfter(ds))) return false;
      if (useFilter &&
          _roomFilter != null &&
          b.roomId.toString() != _roomFilter.toString()) {
        return false;
      }
      return true;
    }).toList();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.plusJakartaSans(fontSize: 12)),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  // ---------------------------------------------------------------- BUILD
  @override
  Widget build(BuildContext context) {
    if (_loading && _rooms.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Coba lagi')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildTodayStatus(),
          const SizedBox(height: 16),
          _buildRoomFilter(),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 1000;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildCalendar()),
                  const SizedBox(width: 16),
                  SizedBox(width: 360, child: _buildDayPanel()),
                ],
              );
            }
            return Column(children: [
              _buildCalendar(),
              const SizedBox(height: 16),
              _buildDayPanel(),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Booking Ruang Meeting',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(width: 12),
        IconButton(
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left)),
        Text('${_namaBulan[_month.month - 1]} ${_month.year}',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w600)),
        IconButton(
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_right)),
        TextButton(onPressed: _goToday, child: const Text('Hari ini')),
        IconButton(
            tooltip: 'Muat ulang',
            onPressed: _load,
            icon: const Icon(Icons.refresh)),
        ElevatedButton.icon(
          onPressed: () => _showBookingDialog(day: _selectedDay),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Booking'),
        ),
      ],
    );
  }

  Widget _buildTodayStatus() {
    if (_rooms.isEmpty) {
      return Text('Belum ada data ruang meeting.',
          style: GoogleFonts.plusJakartaSans(color: Colors.black54));
    }
    final now = _toWib(DateTime.now());
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _rooms.map((room) {
        final list = _todayBookings
            .where((b) => b.roomId.toString() == room.id.toString())
            .toList();
        _Booking? current;
        _Booking? next;
        for (final b in list) {
          if (!b.start.isAfter(now) && b.end.isAfter(now)) {
            current = b;
          } else if (b.start.isAfter(now) && next == null) {
            next = b;
          }
        }
        final color = _roomColor(room.id);
        final String status = current != null
            ? 'Terpakai sampai ${_hm(current.end)}'
            : (next != null
                ? 'Kosong, berikutnya ${_hm(next.start)}'
                : 'Kosong');
        return Container(
          width: 260,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: color, width: 5)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(room.name,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(status,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color:
                          current != null ? Colors.red[700] : Colors.green[700],
                      fontWeight: FontWeight.w600)),
              if (current != null)
                Text(current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: Colors.black54)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRoomFilter() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Semua ruang', style: TextStyle(fontSize: 13)),
          selected: _roomFilter == null,
          onSelected: (_) => setState(() => _roomFilter = null),
        ),
        ..._rooms.map((r) => ChoiceChip(
              avatar:
                  CircleAvatar(backgroundColor: _roomColor(r.id), radius: 6),
              label: Text(r.name, style: const TextStyle(fontSize: 13)),
              selected: _roomFilter != null &&
                  _roomFilter.toString() == r.id.toString(),
              onSelected: (_) => setState(() => _roomFilter = r.id),
            )),
      ],
    );
  }

  Widget _buildCalendar() {
    final first = DateTime.utc(_month.year, _month.month, 1);
    final lead = first.weekday - 1; // Senin = 0
    final days = DateTime.utc(_month.year, _month.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();
    final now = _toWib(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: _namaHari
                .map((h) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: Text(h.substring(0, 3),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black54)),
                        ),
                      ),
                    ))
                .toList(),
          ),
          for (int r = 0; r < rows; r++)
            Row(
              children: [
                for (int c = 0; c < 7; c++)
                  Expanded(
                      child: _buildDayCell(r * 7 + c - lead + 1, days, now)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDayCell(int dayNum, int days, DateTime now) {
    final border = Border(
      top: BorderSide(color: Colors.grey.shade200),
      left: BorderSide(color: Colors.grey.shade200),
    );
    if (dayNum < 1 || dayNum > days) {
      return Container(
        height: 96,
        decoration: BoxDecoration(color: Colors.grey.shade50, border: border),
      );
    }
    final date = DateTime.utc(_month.year, _month.month, dayNum);
    final items = _forDay(_bookings, date);
    final isToday = _sameDay(date, now);
    final isSelected = _sameDay(date, _selectedDay);

    return InkWell(
      onTap: () => setState(() => _selectedDay = date),
      child: Container(
        height: 96,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.08) : Colors.white,
          border: border,
        ),
        child: ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday ? Colors.blue[700] : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text('$dayNum',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isToday ? Colors.white : Colors.black87)),
              ),
              const SizedBox(height: 2),
              ...items.take(3).map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: _roomColor(b.roomId),
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text('${_hm(b.start)} ${b.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(fontSize: 10)),
                        ),
                      ],
                    ),
                  )),
              if (items.length > 3)
                Text('+${items.length - 3} lagi',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayPanel() {
    final day = _selectedDay;
    final dayBookings = _forDay(_bookings, day);
    final shownRooms = _roomFilter == null
        ? _rooms
        : _rooms
            .where((r) => r.id.toString() == _roomFilter.toString())
            .toList();
    final dow = _namaHari[day.weekday - 1];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$dow, ${day.day} ${_namaBulan[day.month - 1]} ${day.year}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, fontWeight: FontWeight.bold)),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton.icon(
              onPressed: () => _showBookingDialog(day: day),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Tambah booking di tanggal ini'),
            ),
          ),
          const SizedBox(height: 8),
          for (final room in shownRooms) ...[
            _buildRoomSection(
              room,
              dayBookings
                  .where((b) => b.roomId.toString() == room.id.toString())
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildRoomSection(_Room room, List<_Booking> list) {
    final color = _roomColor(room.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 10, height: 10, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                room.capacity != null
                    ? '${room.name} • ${room.capacity} orang'
                    : room.name,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (list.isEmpty)
          Text('Kosong seharian',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: Colors.green[700]))
        else
          ...list.map((b) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(left: BorderSide(color: color, width: 4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_hm(b.start)} - ${_hm(b.end)}',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          Text(b.title,
                              style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                          if (b.pic.isNotEmpty)
                            Text('PIC: ${b.pic}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: Colors.black54)),
                          if (b.notes.isNotEmpty)
                            Text(b.notes,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: Colors.black54)),
                        ],
                      ),
                    ),
                    if (_canManage(b)) ...[
                      IconButton(
                        tooltip: 'Ubah',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _showBookingDialog(existing: b),
                      ),
                      IconButton(
                        tooltip: 'Batalkan',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.delete_outline,
                            size: 18, color: Colors.red[700]),
                        onPressed: () => _cancelBooking(b),
                      ),
                    ],
                  ],
                ),
              )),
      ],
    );
  }

  // --------------------------------------------------------------- ACTIONS
  Future<void> _cancelBooking(_Booking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Batalkan booking?',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.bold)),
        content: Text(
            '${b.title}\n${_roomById(b.roomId)?.name ?? ''}, ${_hm(b.start)} - ${_hm(b.end)}',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Tidak', style: TextStyle(fontSize: 13))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Ya, batalkan', style: TextStyle(fontSize: 13))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client
          .from('meeting_bookings')
          .update({'status': 'cancelled'}).eq('id', b.id);
      _snack('Booking dibatalkan');
      await _load();
    } catch (e) {
      _snack('Gagal membatalkan booking: $e', error: true);
    }
  }

  Future<void> _showBookingDialog({_Booking? existing, DateTime? day}) async {
    if (_rooms.isEmpty) {
      _snack('Belum ada data ruang meeting.', error: true);
      return;
    }

    dynamic roomId = existing?.roomId ?? _roomFilter ?? _rooms.first.id;
    final base = existing != null ? existing.start : (day ?? _selectedDay);
    DateTime date = DateTime.utc(base.year, base.month, base.day);
    TimeOfDay startT = existing != null
        ? TimeOfDay(hour: existing.start.hour, minute: existing.start.minute)
        : const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endT = existing != null
        ? TimeOfDay(hour: existing.end.hour, minute: existing.end.minute)
        : const TimeOfDay(hour: 10, minute: 0);
    final titleC = TextEditingController(text: existing?.title ?? '');
    final picC = TextEditingController(text: existing?.pic ?? _myName);
    final notesC = TextEditingController(text: existing?.notes ?? '');
    bool saving = false;
    String? errorText;

    // Gaya dialog: ringkas & konsisten (isi 13, label 12, judul/tombol 13-15)
    const TextStyle fieldStyle = TextStyle(fontSize: 13, color: Colors.black87);
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        );

    Widget pickerField(String label, String value, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: deco(label),
          child: Text(value, style: fieldStyle),
        ),
      );
    }

    Widget h24(BuildContext c, Widget? child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!);

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> save() async {
          final title = titleC.text.trim();
          if (title.isEmpty) {
            setD(() => errorText = 'Agenda / judul meeting wajib diisi');
            return;
          }
          final s = DateTime.utc(
              date.year, date.month, date.day, startT.hour, startT.minute);
          final e = DateTime.utc(
              date.year, date.month, date.day, endT.hour, endT.minute);
          if (!e.isAfter(s)) {
            setD(() => errorText = 'Jam selesai harus setelah jam mulai');
            return;
          }
          setD(() {
            saving = true;
            errorText = null;
          });
          try {
            final payload = {
              'room_id': roomId,
              'title': title,
              'pic_name': picC.text.trim(),
              'notes': notesC.text.trim(),
              'start_at': _fromWib(s).toIso8601String(),
              'end_at': _fromWib(e).toIso8601String(),
            };
            final client = Supabase.instance.client;
            if (existing == null) {
              await client.from('meeting_bookings').insert(payload);
            } else {
              await client
                  .from('meeting_bookings')
                  .update(payload)
                  .eq('id', existing.id);
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          } on PostgrestException catch (err) {
            setD(() {
              saving = false;
              errorText = err.code == '23P01'
                  ? 'Ruang sudah dibooking pada jam tersebut. Pilih jam atau ruang lain.'
                  : 'Gagal menyimpan: ${err.message}';
            });
          } catch (err) {
            setD(() {
              saving = false;
              errorText = 'Gagal menyimpan: $err';
            });
          }
        }

        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          title: Text(
            existing == null ? 'Tambah Booking' : 'Ubah Booking',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 4),
                  InputDecorator(
                    decoration: deco('Ruang'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<dynamic>(
                        value: roomId,
                        isExpanded: true,
                        isDense: true,
                        style: fieldStyle,
                        items: _rooms
                            .map((r) => DropdownMenuItem<dynamic>(
                                value: r.id,
                                child: Text(r.name, style: fieldStyle)))
                            .toList(),
                        onChanged:
                            saving ? null : (v) => setD(() => roomId = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  pickerField(
                    'Tanggal',
                    '${date.day} ${_namaBulan[date.month - 1]} ${date.year}',
                    () async {
                      final p = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime(date.year, date.month, date.day),
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2100),
                      );
                      if (p != null) {
                        setD(() => date = DateTime.utc(p.year, p.month, p.day));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: pickerField(
                          'Mulai',
                          startT.format(ctx),
                          () async {
                            final p = await showTimePicker(
                                context: ctx,
                                initialTime: startT,
                                builder: h24);
                            if (p != null) setD(() => startT = p);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pickerField(
                          'Selesai',
                          endT.format(ctx),
                          () async {
                            final p = await showTimePicker(
                                context: ctx, initialTime: endT, builder: h24);
                            if (p != null) setD(() => endT = p);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleC,
                    style: fieldStyle,
                    decoration: deco('Agenda Meeting'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: picC,
                    style: fieldStyle,
                    decoration: deco('PIC'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesC,
                    maxLines: 2,
                    style: fieldStyle,
                    decoration: deco('Catatan (opsional)'),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(errorText!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, false),
                child: const Text('Batal', style: TextStyle(fontSize: 13))),
            ElevatedButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Simpan', style: TextStyle(fontSize: 13)),
            ),
          ],
        );
      }),
    );

    if (saved == true) {
      setState(() {
        _selectedDay = date;
        _month = DateTime.utc(date.year, date.month, 1);
      });
      _snack(existing == null ? 'Booking disimpan' : 'Booking diperbarui');
      await _load();
    }
  }
}
