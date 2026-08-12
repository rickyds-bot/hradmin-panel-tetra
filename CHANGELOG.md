# Changelog

Semua perubahan penting pada aplikasi ini dicatat di file ini.

## [1.0.0] - 2026-08-06

Rilis pertama.

### Fitur

**Absensi**
- Absen masuk/pulang dengan validasi GPS + foto selfie + face detection
- Konfigurasi titik/radius lokasi absen lewat web admin
- Mode "absen bebas lokasi" (dapat diaktifkan/nonaktifkan dari web admin)

**Profil Karyawan**
- Form profil karyawan: data diri, data keluarga, dan kontak darurat

**Cuti / Izin / Lembur**
- Pengajuan cuti/izin dan lembur oleh karyawan
- Approval berjenjang oleh atasan per divisi/departemen
- Notifikasi pengajuan & status approval via push notification (FCM)

**Absensi — Notifikasi**
- Notifikasi check-in/check-out via local notification

**Laporan**
- Export laporan absensi, cuti/izin, dan lembur ke XLSX & PDF dari admin dashboard
- Export PDF laporan lembur langsung dari aplikasi mobile (karyawan)

**Admin Dashboard**
- Monitoring absensi seluruh karyawan
- Manajemen data karyawan (tambah/edit/hapus)
- Penambahan role admin 

### Platform

- Android: distribusi internal
- iOS: belum tersedia pada rilis ini, disiapkan menyusul
- Web admin dashboard: hosting di Cloudflare Pages/Worker
- Backend: Supabase

---

<!--
Template untuk rilis berikutnya:

## [x.y.z] - YYYY-MM-DD

### Ditambahkan
-

### Diperbaiki
-

### Diubah
-
-->
