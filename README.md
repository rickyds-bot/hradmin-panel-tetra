# Aplikasi Absensi Karyawan — PT. Tetra

Aplikasi absensi karyawan berbasis mobile (Flutter) dengan web admin dashboard, menggunakan Supabase sebagai backend.

**Status: Sudah selesai dikembangkan, dalam proses go-live.**

## Ringkasan

- **Nama internal**: `mobile_absensi`
- **Platform**:
  - Mobile app karyawan — Flutter (Android/iOS)
  - Mobile app admin - Flutter (Android)
  - Web admin dashboard — Flutter Web, di-hosting via **Cloudflare Pages/Worker**
- **Backend**: Supabase (Auth, Database, Storage, RLS)
- **CI/CD mobile**: Codemagic (`codemagic.yaml`)
- **Repo**: [rickyds-bot/hradmin-panel-tetra](https://github.com/rickyds-bot/hradmin-panel-tetra)

## Fitur Utama

- Absen masuk/pulang dengan validasi **GPS + foto selfie**, dilengkapi **face detection**
- Konfigurasi lokasi absensi dilakukan lewat **web admin**:
  - Set titik/radius lokasi absen
  - Bisa mengaktifkan mode **"absen bebas lokasi"** (tanpa validasi GPS) per kebutuhan
- Form **profil karyawan**: data diri, data keluarga, dan kontak darurat
- Riwayat absensi, cuti/izin & lembur karyawan
- Pengajuan cuti/izin dan lembur oleh karyawan
- Approval pengajuan cuti/izin/lembur oleh atasan (admin, supervisor & manager), berjenjang per **divisi/departemen**
- Notifikasi:
  - Check-in/check-out absen → **local notification**
  - Pengajuan & status approval cuti/izin/lembur → **push notification (FCM)**
- Laporan & export:
  - Laporan absensi, cuti/izin, dan lembur → export **XLSX & PDF** (dari admin dashboard)
  - Karyawan bisa export **PDF laporan lembur** langsung dari aplikasi mobile
- Dashboard admin: monitoring absensi seluruh karyawan
- Manajemen data karyawan (tambah/edit/hapus)
- Log Aktifitas Karyawan 
- Form Notifikasi Pemberitahun/Pengumuman

## Struktur Project

```
lib/            # kode utama aplikasi Flutter (app karyawan + admin)
supabase/       # konfigurasi & migration database Supabase
web/            # build target web (admin dashboard)
android/ ios/   # konfigurasi platform mobile
codemagic.yaml  # konfigurasi CI/CD build mobile

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
