# Aplikasi Absensi Karyawan — PT. Tetra

Aplikasi absensi karyawan berbasis mobile (Flutter) dengan web admin dashboard, menggunakan Supabase sebagai backend.

**Status: Sudah selesai dikembangkan, dalam proses go-live.**

## Ringkasan

- **Nama internal**: `mobile_absensi`
- **Platform**:
  - Mobile app karyawan - Flutter (Android/iOS)
  - Mobile app admin - Flutter (Android)
  - Web admin dashboard - Flutter Web, di-hosting via **Cloudflare Pages/Worker**
  - Firebase Console & Google Cloud Console
- **Backend**: Supabase (Auth, Database, Storage, RLS, Edge Function, Webhook)
- **CI/CD mobile**: Codemagic (`codemagic.yaml`)
- **Repo**: [rickyds-bot/hradmin-panel-tetra](https://github.com/rickyds-bot/hradmin-panel-tetra)

## Fitur Utama

- Register Karyawan konfirmasi by Email 
- Register Data Wajah kebutuhan Face Detection
- Absen Check-in/Check-out dengan validasi **GPS + Foto Selfie**, dilengkapi **Face Detection**
- Absen Check-in/Check-out hanya bs dilakukan 1x (1 hari)
- Riwayat Absensi, Cuti/Izin & Lembur Karyawan
- Pengajuan Cuti/Izin dan Lembur oleh Karyawan
- Approval pengajuan Cuti/Izin/Lembur oleh Atasan (Admin, Supervisor & Manager), berjenjang per **Divisi/Departemen**
- Karyawan bisa Export **PDF Laporan Lembur** langsung dari Aplikasi Mobile
- Form **Profil Karyawan**: Data Diri, Data Keluarga, dan Kontak Darurat
- Notifikasi:
  - Check-in/Check-out Absen → **local notification**
  - Pengajuan & Status Approval Cuti/Izin/Lembur → **push notification (FCM)**

- Dashboard Admin: Monitoring Absensi seluruh Karyawan
  - Manajemen Data Karyawan (Tambah/Edit/Aktif & Non-Aktif)
  - Log Aktifitas Karyawan 
  - Form Input & Notifikasi Pemberitahun/Pengumuman
  - Sinkron Kalendar Hari Libur/Tgl Merah IDN
  - Konfigurasi Lokasi Absensi dilakukan lewat **Admin Dashboard**:
  - Set Titik/Radius Lokasi Absen
  - Bisa mengaktifkan mode **"Absen Bebas Lokasi"** (tanpa validasi GPS) per kebutuhan
- Laporan & Export:
  - Laporan Absensi, Cuti/Izin, dan Lembur → Export **XLSX & PDF** (dari Admin Dashboard)
  

## Struktur Project

```
lib/            # kode utama aplikasi Flutter (app Karyawan + Admin)
supabase/       # konfigurasi & migration database Supabase
web/            # build target web (Admin Dashboard)
android/ ios/   # konfigurasi Platform Mobile
codemagic.yaml  # konfigurasi CI/CD Build Mobile

```


## Menjalankan Secara Lokal

```bash
flutter pub get
flutter build apk --flavor karyawan -t lib/main_karyawan.dart --release --split-per-abi
flutter build apk --flavor admin -t lib/main_admin.dart --release --split-per-abi

```

Untuk target web (admin dashboard):
```bash
flutter run -d chrome -t lib/main_web.dart
flutter build web --target=lib/main_web.dart --release --no-wasm-dry-run

```

## Konfigurasi Supabase

Project ini membutuhkan environment/konfigurasi berikut :

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`


## Dokumentasi Terkait

- [`DEPLOYMENT.md`](./DEPLOYMENT.md) — panduan build & go-live
- [`CHANGELOG.md`](./CHANGELOG.md) 

## Kontak / PIC

- Ricky D. Surya (ricky@tetra.co.id)
