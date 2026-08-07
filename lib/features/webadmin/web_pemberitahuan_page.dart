import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_absensi/features/core/utils/app_logger.dart';

class WebPemberitahuanPage extends StatefulWidget {
  const WebPemberitahuanPage({super.key});

  @override
  State<WebPemberitahuanPage> createState() => _WebPemberitahuanPageState();
}

class _WebPemberitahuanPageState extends State<WebPemberitahuanPage> {
  List<dynamic> _announcementsList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
  }

  Future<void> _fetchAnnouncements() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('announcements')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        _announcementsList = data;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal mengambil data: $e',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Fungsi Tambahan: Toggle Status Aktif ---
  Future<void> _toggleActiveStatus(
      Map<String, dynamic> item, bool newValue) async {
    // 1. Update UI secara lokal terlebih dahulu agar terasa responsif
    setState(() {
      final index = _announcementsList
          .indexWhere((element) => element['id'] == item['id']);
      if (index != -1) {
        _announcementsList[index]['is_active'] = newValue;
      }
    });

    try {
      // 2. Update data ke Supabase
      await Supabase.instance.client
          .from('announcements')
          .update({'is_active': newValue}).eq('id', item['id']);

      String statusStr = newValue ? 'mengaktifkan' : 'menonaktifkan';
      await AppLogger.log(
        activity: 'Berhasil $statusStr pengumuman: "${item['title']}"',
        module: 'Pemberitahuan',
      );
    } catch (e) {
      // 3. Jika gagal, kembalikan status seperti semula
      setState(() {
        final index = _announcementsList
            .indexWhere((element) => element['id'] == item['id']);
        if (index != -1) {
          _announcementsList[index]['is_active'] = !newValue;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal mengubah status: $e',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteAnnouncement(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Konfirmasi Hapus',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Yakin ingin menghapus pengumuman "${item['title'] ?? 'Tanpa Judul'}"?',
          style: GoogleFonts.plusJakartaSans(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Batal',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Hapus',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client
            .from('announcements')
            .delete()
            .eq('id', item['id']);

        await AppLogger.log(
          activity: 'Menghapus pengumuman: "${item['title']}"',
          module: 'Pemberitahuan',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Pengumuman berhasil dihapus',
                style: GoogleFonts.plusJakartaSans(fontSize: 13),
              ),
            ),
          );
          _fetchAnnouncements();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Gagal menghapus: $e',
                style: GoogleFonts.plusJakartaSans(fontSize: 13),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  Color _getPriorityColor(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'penting':
        return Colors.orange;
      case 'darurat':
        return Colors.red;
      case 'info':
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Kelola Pengumuman',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) =>
                        AddAnnouncementDialog(onSuccess: _fetchAnnouncements),
                  );
                },
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: Text(
                  'Buat Pengumuman',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[200]!),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _announcementsList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_off_outlined,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Belum ada data pengumuman.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              showCheckboxColumn: false,
                              headingRowColor: WidgetStateProperty.all(
                                Colors.grey[50],
                              ),
                              dataRowMaxHeight: 65,
                              headingTextStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              dataTextStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                              columns: const [
                                DataColumn(label: Text('No')),
                                DataColumn(label: Text('Judul')),
                                DataColumn(label: Text('Isi Pemberitahuan')),
                                DataColumn(label: Text('Prioritas')),
                                DataColumn(label: Text('Status Aktif')),
                                DataColumn(label: Text('Waktu Dibuat')),
                                DataColumn(label: Text('Action')),
                              ],
                              rows: List<DataRow>.generate(
                                _announcementsList.length,
                                (index) {
                                  final item = _announcementsList[index];
                                  final bool isActive =
                                      item['is_active'] ?? true;
                                  final String priority =
                                      item['priority'] ?? 'info';

                                  return DataRow(
                                    cells: [
                                      DataCell(Text('${index + 1}')),
                                      DataCell(
                                        Text(
                                          item['title'] ?? '-',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 250,
                                          child: Text(
                                            item['content'] ?? '-',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getPriorityColor(
                                              priority,
                                            ).withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            priority.toUpperCase(),
                                            style: TextStyle(
                                              color:
                                                  _getPriorityColor(priority),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Switch(
                                          value: isActive,
                                          activeColor: Colors.blue,
                                          onChanged: (bool value) {
                                            _toggleActiveStatus(item, value);
                                          },
                                        ),
                                      ),
                                      DataCell(
                                        Text(_formatDate(item['created_at'])),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // --- TAMBAHAN TOMBOL EDIT ---
                                            IconButton(
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                color: Colors.blue,
                                                size: 20,
                                              ),
                                              tooltip: 'Edit Pengumuman',
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  barrierDismissible: false,
                                                  builder: (context) =>
                                                      AddAnnouncementDialog(
                                                    announcementData: item,
                                                    onSuccess:
                                                        _fetchAnnouncements,
                                                  ),
                                                );
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.red,
                                                size: 20,
                                              ),
                                              tooltip: 'Hapus Pengumuman',
                                              onPressed: () =>
                                                  _deleteAnnouncement(item),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class AddAnnouncementDialog extends StatefulWidget {
  final Map<String, dynamic>?
      announcementData; // TAMBAHAN: Untuk menampung data edit
  final VoidCallback onSuccess;

  const AddAnnouncementDialog(
      {super.key, this.announcementData, required this.onSuccess});

  @override
  State<AddAnnouncementDialog> createState() => _AddAnnouncementDialogState();
}

class _AddAnnouncementDialogState extends State<AddAnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String _priority = 'info';
  bool _isActive = true;
  final List<String> _priorityList = ['info', 'penting', 'darurat'];

  @override
  void initState() {
    super.initState();
    // Jika ada data yang dilempar (Mode Edit), isi kolom-kolomnya
    if (widget.announcementData != null) {
      _titleCtrl.text = widget.announcementData!['title'] ?? '';
      _contentCtrl.text = widget.announcementData!['content'] ?? '';
      _priority = widget.announcementData!['priority'] ?? 'info';
      _isActive = widget.announcementData!['is_active'] ?? true;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  // --- FUNGSI TAMBAHAN: Menyisipkan Format Teks HTML ---
  void _insertFormat(String prefix, String suffix) {
    final text = _contentCtrl.text;
    final selection = _contentCtrl.selection;

    // Jika pengguna tidak menyeleksi teks apapun, tambahkan di akhir
    if (selection.start == -1 || selection.end == -1) {
      _contentCtrl.text = text + prefix + suffix;
      _contentCtrl.selection = TextSelection.collapsed(
        offset: _contentCtrl.text.length - suffix.length,
      );
      return;
    }

    // Jika pengguna menyeleksi teks, apit teks tersebut
    final selectedText = text.substring(selection.start, selection.end);
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      '$prefix$selectedText$suffix',
    );

    _contentCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + prefix.length + selectedText.length,
      ),
    );
  }

  Future<void> _saveAnnouncement() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final payload = {
        'title': _titleCtrl.text,
        'content': _contentCtrl.text,
        'priority': _priority,
        'is_active': _isActive,
      };

      // Cek apakah ini mode Edit atau Tambah Baru
      if (widget.announcementData == null) {
        // Mode Tambah Baru
        await Supabase.instance.client.from('announcements').insert(payload);
        await AppLogger.log(
          activity: 'Membuat pengumuman baru: "${_titleCtrl.text}"',
          module: 'Pemberitahuan',
        );
      } else {
        // Mode Edit
        await Supabase.instance.client
            .from('announcements')
            .update(payload)
            .eq('id', widget.announcementData!['id']);
        await AppLogger.log(
          activity: 'Memperbarui pengumuman: "${_titleCtrl.text}"',
          module: 'Pemberitahuan',
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.announcementData == null
                  ? 'Pengumuman berhasil dibuat!'
                  : 'Pengumuman berhasil diperbarui!',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.announcementData != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          // --- TAMBAHKAN SingleChildScrollView DI SINI ---
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isEdit ? Colors.orange[50] : Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isEdit ? Icons.edit_note : Icons.campaign,
                        color: isEdit ? Colors.orange : Colors.blue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      isEdit ? 'Edit Pengumuman' : 'Buat Pengumuman Baru',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(),
                ),
                TextFormField(
                  controller: _titleCtrl,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Judul Pengumuman',
                    labelStyle: GoogleFonts.plusJakartaSans(
                      color: Colors.black54,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  validator: (val) =>
                      val == null || val.isEmpty ? 'Judul wajib diisi' : null,
                ),
                const SizedBox(height: 16),

                // --- TAMBAHAN: Toolbar Format Teks ---
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.format_bold, size: 20),
                        tooltip: 'Tebal (Bold)',
                        onPressed: () => _insertFormat('<b>', '</b>'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.format_italic, size: 20),
                        tooltip: 'Miring (Italic)',
                        onPressed: () => _insertFormat('<i>', '</i>'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.format_underline, size: 20),
                        tooltip: 'Garis Bawah (Underline)',
                        onPressed: () => _insertFormat('<u>', '</u>'),
                      ),
                    ],
                  ),
                ),
                // Field Konten
                TextFormField(
                  controller: _contentCtrl,
                  maxLines: 5,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Ketik isi pengumuman di sini...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      color: Colors.black54,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      borderSide: BorderSide(
                          color: Colors.grey, width: 0.5), // Match border
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  validator: (val) =>
                      val == null || val.isEmpty ? 'Konten wajib diisi' : null,
                ),

                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _priority,
                  items: _priorityList
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                            e.toUpperCase(),
                            style: GoogleFonts.plusJakartaSans(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => _priority = val ?? 'info'),
                  decoration: InputDecoration(
                    labelText: 'Prioritas',
                    labelStyle: GoogleFonts.plusJakartaSans(
                      color: Colors.black54,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: Text(
                    'Status Aktif',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    'Pengumuman aktif akan tampil di aplikasi karyawan',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  value: _isActive,
                  onChanged: (val) => setState(() => _isActive = val),
                  activeColor: Colors.blue,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Batal',
                        style: GoogleFonts.plusJakartaSans(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveAnnouncement,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              isEdit
                                  ? 'Perbarui Pengumuman'
                                  : 'Simpan Pengumuman',
                              style: GoogleFonts.plusJakartaSans(fontSize: 13),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
