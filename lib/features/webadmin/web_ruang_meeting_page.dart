import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
  final String type; // 'room' | 'vehicle'
  _Room.fromMap(Map<String, dynamic> m)
      : id = m['id'],
        type = (m['resource_type'] ?? 'room').toString(),
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
  List<_Room> _allRooms = [];
  String _type = 'room'; // 'room' | 'vehicle'
  bool get _isVehicle => _type == 'vehicle';
  List<_Room> get _rooms => _allRooms.where((r) => r.type == _type).toList();
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
    for (final r in _allRooms) {
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
        _allRooms = (roomRows as List)
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
    final ids = _rooms.map((r) => r.id.toString()).toSet();
    return list.where((b) {
      if (!ids.contains(b.roomId.toString())) return false;
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
    if (_loading && _allRooms.isEmpty && _error == null) {
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
          _buildTypeSwitch(),
          const SizedBox(height: 16),
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

  Widget _buildTypeSwitch() {
    return SegmentedButton<String>(
      style: ButtonStyle(
        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13)),
      ),
      segments: const [
        ButtonSegment(
            value: 'room',
            icon: Icon(Icons.meeting_room_outlined, size: 18),
            label: Text('Ruang Meeting')),
        ButtonSegment(
            value: 'vehicle',
            icon: Icon(Icons.directions_car_outlined, size: 18),
            label: Text('Kendaraan')),
      ],
      selected: {_type},
      onSelectionChanged: (v) => setState(() {
        _type = v.first;
        _roomFilter = null;
      }),
    );
  }

  String _roomSubtitle(_Room r) {
    final parts = <String>[r.name];
    if (r.type == 'vehicle') {
      if (r.capacity != null) parts.add('${r.capacity} kursi');
      if (r.facilities.isNotEmpty) parts.add(r.facilities);
    } else if (r.capacity != null) {
      parts.add('${r.capacity} orang');
    }
    return parts.join(' • ');
  }

  Widget _buildHeader() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(_isVehicle ? 'Booking Kendaraan' : 'Booking Ruang Meeting',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(width: 12),
        IconButton(
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left)),
        Text('${_namaBulan[_month.month - 1]} ${_month.year}',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w600)),
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
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Booking'),
        ),
      ],
    );
  }

  Widget _buildTodayStatus() {
    if (_rooms.isEmpty) {
      return Text(
          _isVehicle
              ? 'Belum ada data kendaraan.'
              : 'Belum ada data ruang meeting.',
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
              if (room.type == 'vehicle' && room.facilities.isNotEmpty)
                Text(room.facilities,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: Colors.black54)),
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
              icon: const Icon(Icons.add, size: 16),
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
                _roomSubtitle(room),
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

  // Menit sejak 00:00 -> "HH:mm"
  String _fmtMin(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  String _durasi(int m) {
    final h = m ~/ 60;
    final r = m % 60;
    if (h > 0 && r > 0) return '$h jam $r menit';
    if (h > 0) return '$h jam';
    return '$r menit';
  }

  /// Slot yang sudah terbooking pada [date] untuk ruang/kendaraan [roomId],
  /// dalam bentuk [menitMulai, menitSelesai] sejak 00:00 (WIB).
  Future<List<List<int>>> _fetchBusy(
      dynamic roomId, DateTime date, dynamic excludeId) async {
    try {
      final base = DateTime.utc(date.year, date.month, date.day);
      final dayStart = _fromWib(base);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final rows = await Supabase.instance.client
          .from('meeting_bookings')
          .select('id,start_at,end_at')
          .eq('room_id', roomId)
          .eq('status', 'active')
          .lt('start_at', dayEnd.toIso8601String())
          .gt('end_at', dayStart.toIso8601String());
      int cl(int v) => v < 0 ? 0 : (v > 1440 ? 1440 : v);
      final out = <List<int>>[];
      for (final r in rows as List) {
        if (excludeId != null && r['id'].toString() == excludeId.toString()) {
          continue;
        }
        final s = _toWib(DateTime.parse(r['start_at'].toString()));
        final e = _toWib(DateTime.parse(r['end_at'].toString()));
        out.add([
          cl(s.difference(base).inMinutes),
          cl(e.difference(base).inMinutes)
        ]);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _showBookingDialog({_Booking? existing, DateTime? day}) async {
    if (_rooms.isEmpty) {
      _snack(
          _isVehicle
              ? 'Belum ada data kendaraan.'
              : 'Belum ada data ruang meeting.',
          error: true);
      return;
    }

    dynamic roomId = existing?.roomId ?? _roomFilter ?? _rooms.first.id;
    final base = existing != null ? existing.start : (day ?? _selectedDay);
    DateTime date = DateTime.utc(base.year, base.month, base.day);

    int startMin = existing != null
        ? existing.start.hour * 60 + existing.start.minute
        : 9 * 60;
    int endMin = existing != null
        ? (existing.end.day == existing.start.day
            ? existing.end.hour * 60 + existing.end.minute
            : 1440)
        : 10 * 60;

    // Rentang garis waktu: 07:00-19:00, otomatis melebar kalau data lama di luar itu.
    final int dayStartMin = math.min(7 * 60, (startMin ~/ 60) * 60);
    final int dayEndMin = math.max(19 * 60, ((endMin + 59) ~/ 60) * 60);

    final titleC = TextEditingController(text: existing?.title ?? '');
    final picC = TextEditingController(text: existing?.pic ?? _myName);
    final notesC = TextEditingController(text: existing?.notes ?? '');
    bool saving = false;
    String? errorText;

    List<List<int>> busy = await _fetchBusy(roomId, date, existing?.id);

    bool overlaps(int s, int e) => busy.any((b) => s < b[1] && e > b[0]);

    void pickDefault() {
      final order = <int>[];
      for (int m = 9 * 60; m < dayEndMin; m += 30) {
        order.add(m);
      }
      for (int m = dayStartMin; m < 9 * 60; m += 30) {
        order.add(m);
      }
      for (final m in order) {
        if (!overlaps(m, m + 30)) {
          startMin = m;
          endMin =
              (m + 60 <= dayEndMin && !overlaps(m, m + 60)) ? m + 60 : m + 30;
          return;
        }
      }
    }

    if (existing == null && overlaps(startMin, endMin)) pickDefault();

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

    final bool vehicle = _isVehicle;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> refreshBusy() async {
          final b = await _fetchBusy(roomId, date, existing?.id);
          if (!ctx.mounted) return;
          setD(() {
            busy = b;
            if (overlaps(startMin, endMin)) pickDefault();
          });
        }

        Future<void> save() async {
          final title = titleC.text.trim();
          if (title.isEmpty) {
            setD(() => errorText = vehicle
                ? 'Tujuan / keperluan wajib diisi'
                : 'Agenda / judul meeting wajib diisi');
            return;
          }
          if (endMin <= startMin) {
            setD(() => errorText = 'Pilih jam pada garis waktu');
            return;
          }
          if (overlaps(startMin, endMin)) {
            setD(() => errorText =
                'Jam yang dipilih bertabrakan dengan booking lain.');
            return;
          }
          final s = DateTime.utc(
              date.year, date.month, date.day, startMin ~/ 60, startMin % 60);
          final e = DateTime.utc(
              date.year, date.month, date.day, endMin ~/ 60, endMin % 60);
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
                  ? 'Sudah dibooking pada jam tersebut. Pilih jam atau pilihan lain.'
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
                fontSize: 15, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  InputDecorator(
                    decoration: deco(vehicle ? 'Kendaraan' : 'Ruang'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<dynamic>(
                        value: roomId,
                        isExpanded: true,
                        isDense: true,
                        style: fieldStyle,
                        items: _rooms
                            .map((r) => DropdownMenuItem<dynamic>(
                                value: r.id,
                                child:
                                    Text(_roomSubtitle(r), style: fieldStyle)))
                            .toList(),
                        onChanged: saving
                            ? null
                            : (v) {
                                setD(() => roomId = v);
                                refreshBusy();
                              },
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
                        refreshBusy();
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  Text('Jam (klik atau geser pada garis waktu)',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 6),
                  _TimeRangeSelector(
                    dayStartMin: dayStartMin,
                    dayEndMin: dayEndMin,
                    startMin: startMin,
                    endMin: endMin,
                    busy: busy,
                    color: _roomColor(roomId),
                    onChanged: (r) => setD(() {
                      startMin = r[0];
                      endMin = r[1];
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_fmtMin(startMin)} - ${_fmtMin(endMin)}   (${_durasi(endMin - startMin)})',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: titleC,
                    style: fieldStyle,
                    decoration: deco(vehicle
                        ? 'Tujuan / keperluan'
                        : 'Agenda / judul meeting'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: picC,
                    style: fieldStyle,
                    decoration: deco(vehicle ? 'Pemesan' : 'PIC / pemesan'),
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

/// Garis waktu horizontal per 30 menit. Klik satu kotak atau geser (drag) untuk
/// memilih rentang jam. Kotak merah = sudah terbooking (tidak bisa dipilih).
class _TimeRangeSelector extends StatefulWidget {
  final int dayStartMin;
  final int dayEndMin;
  final int startMin;
  final int endMin;
  final List<List<int>> busy; // [menitMulai, menitSelesai]
  final Color color;
  final ValueChanged<List<int>> onChanged;

  const _TimeRangeSelector({
    required this.dayStartMin,
    required this.dayEndMin,
    required this.startMin,
    required this.endMin,
    required this.busy,
    required this.color,
    required this.onChanged,
  });

  @override
  State<_TimeRangeSelector> createState() => _TimeRangeSelectorState();
}

class _TimeRangeSelectorState extends State<_TimeRangeSelector> {
  static const int _slot = 30;
  int? _anchor;

  int get _count => (widget.dayEndMin - widget.dayStartMin) ~/ _slot;

  bool _isBusy(int i) {
    final s = widget.dayStartMin + i * _slot;
    final e = s + _slot;
    return widget.busy.any((b) => s < b[1] && e > b[0]);
  }

  int _indexAt(double dx, double width) {
    int i = (dx / (width / _count)).floor();
    if (i < 0) i = 0;
    if (i >= _count) i = _count - 1;
    return i;
  }

  void _select(int anchor, int current) {
    int lo = anchor;
    int hi = anchor;
    if (current >= anchor) {
      for (int i = anchor + 1; i <= current; i++) {
        if (_isBusy(i)) break;
        hi = i;
      }
    } else {
      for (int i = anchor - 1; i >= current; i--) {
        if (_isBusy(i)) break;
        lo = i;
      }
    }
    widget.onChanged([
      widget.dayStartMin + lo * _slot,
      widget.dayStartMin + (hi + 1) * _slot,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final selS = (widget.startMin - widget.dayStartMin) ~/ _slot;
    final selE = (widget.endMin - widget.dayStartMin) ~/ _slot; // eksklusif

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final cell = w / _count;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 14,
            width: w,
            child: Stack(
              children: [
                for (int i = 0; i < _count; i++)
                  if ((widget.dayStartMin + i * _slot) % 60 == 0)
                    Positioned(
                      left: i * cell,
                      child: Text(
                        ((widget.dayStartMin + i * _slot) ~/ 60)
                            .toString()
                            .padLeft(2, '0'),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.black54),
                      ),
                    ),
              ],
            ),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // 'down' = titik awal geser dihitung dari posisi klik pertama
              dragStartBehavior: DragStartBehavior.down,
              onTapDown: (d) {
                final i = _indexAt(d.localPosition.dx, w);
                if (_isBusy(i)) {
                  _anchor = null;
                  return;
                }
                _anchor = i;
                _select(i, i);
              },
              onHorizontalDragStart: (d) {
                final i = _indexAt(d.localPosition.dx, w);
                if (_isBusy(i)) {
                  _anchor = null;
                  return;
                }
                _anchor = i;
                _select(i, i);
              },
              onHorizontalDragUpdate: (d) {
                final a = _anchor;
                if (a == null) return;
                _select(a, _indexAt(d.localPosition.dx, w));
              },
              child: Container(
                height: 34,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Row(
                    children: [
                      for (int i = 0; i < _count; i++)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: _isBusy(i)
                                  ? Colors.red.withOpacity(0.25)
                                  : (i >= selS && i < selE
                                      ? widget.color.withOpacity(0.85)
                                      : Colors.white),
                              border: Border(
                                left: BorderSide(
                                  color:
                                      (widget.dayStartMin + i * _slot) % 60 == 0
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade200,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _legend(widget.color.withOpacity(0.85), 'Dipilih'),
              const SizedBox(width: 12),
              _legend(Colors.red.withOpacity(0.25), 'Sudah terbooking'),
              const SizedBox(width: 12),
              _legend(Colors.white, 'Kosong', border: true),
            ],
          ),
        ],
      );
    });
  }

  Widget _legend(Color color, String text, {bool border = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            border: border ? Border.all(color: Colors.grey.shade400) : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ],
    );
  }
}
