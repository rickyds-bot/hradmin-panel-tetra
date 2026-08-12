# Aplikasi Absensi Karyawan — PT. Tetra

Aplikasi absensi karyawan berbasis mobile (Flutter) dengan web admin dashboard, menggunakan Supabase sebagai backend.

**Status: Sudah selesai dikembangkan, dalam proses go-live.**

## Ringkasan

- **Nama internal**: `mobile_absensi`
- **Platform**:
  - Mobile app karyawan — Flutter (Android/iOS)
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
- Riwayat absensi karyawan
- Pengajuan cuti/izin dan lembur oleh karyawan
- Approval pengajuan cuti/izin/lembur oleh atasan, berjenjang per **divisi/departemen**
- Notifikasi:
  - Check-in/check-out absen → **local notification**
  - Pengajuan & status approval cuti/izin/lembur → **push notification (FCM)**
- Laporan & export:
  - Laporan absensi, cuti/izin, dan lembur → export **XLSX & PDF** (dari admin dashboard)
  - Karyawan bisa export **PDF laporan lembur** langsung dari aplikasi mobile
- Dashboard admin: monitoring absensi seluruh karyawan
- Manajemen data karyawan (tambah/edit/hapus)
- _(tambahkan fitur lain yang relevan, misal shift kerja)_

## Struktur Project

```
lib/            # kode utama aplikasi Flutter (app karyawan + admin)
supabase/       # konfigurasi & migration database Supabase
web/            # build target web (admin dashboard)
android/ ios/   # konfigurasi platform mobile
codemagic.yaml  # konfigurasi CI/CD build mobile
# konfigurasi Cloudflare Pages/Worker untuk hosting web admin — sesuaikan nama file (mis. wrangler.toml) dengan yang ada di repo
```

> Catatan: jika `lib/` memisahkan app karyawan dan admin dashboard dalam satu codebase (misal via flavor/target), jelaskan pemisahannya di sini.

## Menjalankan Secara Lokal

```bash
flutter pub get
flutter run
```

Untuk target web (admin dashboard):
```bash
flutter run -d chrome
```

## Konfigurasi Supabase

Project ini membutuhkan environment/konfigurasi berikut (isi sesuai kondisi nyata, jangan simpan nilai rahasia di file ini):

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Lokasi penyimpanan config: _(isi — misal `.env`, `--dart-define`, atau Codemagic environment variables)_

## Dokumentasi Terkait

- [`DEPLOYMENT.md`](./DEPLOYMENT.md) — panduan build & go-live
- [`CHANGELOG.md`](./CHANGELOG.md) — catatan rilis (buat file ini mulai rilis pertama)

## Kontak / PIC

- _(isi nama/kontak yang bertanggung jawab maintain aplikasi ini)_
