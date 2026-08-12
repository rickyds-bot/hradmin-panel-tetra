# Panduan Deployment — Aplikasi Absensi Karyawan

Dokumen ini mencatat langkah-langkah go-live untuk mobile app dan web admin dashboard, supaya proses rilis (dan rilis berikutnya) bisa diulang dengan konsisten.

## 1. Checklist Sebelum Live

- [ ] Semua environment variable Supabase (URL, anon key) sudah diset di tempat yang benar (build config / Codemagic / `.env`)
- [ ] Firebase project untuk FCM sudah dikonfigurasi (`google-services.json` untuk Android, server key/service account untuk kirim notifikasi dari backend)
- [ ] RLS (Row Level Security) policy di Supabase sudah aktif dan diuji untuk masing-masing role (admin, atasan/approver per divisi, karyawan)
- [ ] Alur approval cuti/izin/lembur sudah diuji end-to-end (karyawan ajukan → atasan divisi terkait menerima notifikasi/dapat melihat → approve/reject → status ter-update ke karyawan)
- [ ] Akurasi GPS & face detection sudah diuji di kondisi lapangan nyata (bukan hanya emulator/simulator), termasuk edge case (lokasi lemah sinyal, pencahayaan kurang untuk face detection)
- [ ] Konfigurasi titik/radius lokasi absen di web admin sudah diuji, dan diterapkan dengan benar ke sisi app karyawan
- [ ] Mode "absen bebas lokasi" (toggle dari web admin) sudah diuji — memastikan saat aktif validasi GPS memang di-skip, dan saat nonaktif validasi kembali berjalan
- [ ] Permission GPS & kamera sudah diminta dan dijelaskan dengan benar di app (Android runtime permission)
- [ ] Form profil karyawan (data diri, keluarga, kontak darurat) sudah diuji — data tersimpan dengan benar dan sesuai kebutuhan privasi/akses (siapa saja yang bisa lihat data ini di admin)
- [ ] FCM (Firebase Cloud Messaging) sudah dikonfigurasi & diuji untuk notifikasi pengajuan/approval cuti-izin-lembur (termasuk uji di kondisi app background/terminated)
- [ ] Local notification untuk check-in/check-out sudah diuji di berbagai kondisi (app dibuka, background, device di-restart)
- [ ] Export laporan (XLSX & PDF) dari admin dashboard sudah diuji dengan data volume besar (bukan hanya data dummy sedikit)
- [ ] Export PDF laporan lembur dari aplikasi mobile sudah diuji (termasuk di device dengan storage terbatas/permission penyimpanan)
- [ ] Data dummy/testing sudah dibersihkan dari database production
- [ ] Akun admin pertama sudah dibuat di Supabase Auth
- [ ] Sudah diuji di device Android & iOS (Menyusul)
- [ ] Web admin dashboard sudah diuji di browser desktop utama (Chrome/Edge)

## 2. Deploy Web Admin Dashboard (Cloudflare Pages/Worker)

```bash
flutter build web --target=lib/main_web.dart --release --no-wasm-dry-run

```
> - Integrasi GITHUB
> - https://hradmin-panel-tetra.prodigalx.workers.dev/  **Cloudflare Worker** 
> - https://hradmin.tetra.co.id
>

## 3. Build & Rilis Mobile App

Repo menggunakan Codemagic (`codemagic.yaml`) untuk CI/CD. Alur umum:

1. Push ke branch yang di-trigger Codemagic (isi nama branch, misal `main` atau `release`)
2. Codemagic menjalankan build otomatis sesuai konfigurasi
3. Hasil build (APK/IPA) didistribusikan ke: internal manual (APK)

### Android — Distribusi Internal
- [ ] Metode distribusi: APK langsung ke karyawan 
- [ ] Versi & build number di `pubspec.yaml` sudah dinaikkan
- [ ] Signing key sudah disiapkan (keystore untuk build release, bukan debug key)
- [ ] Cara update aplikasi ke karyawan sudah ditentukan : distribusi file APK & link download internal

### iOS — Menyusul
Rilis pertama fokus Android saja. Untuk iOS, siapkan lebih awal supaya tidak jadi blocker nanti:
- [ ] Apple Developer Program account sudah aktif
- [ ] Konfigurasi permission `Info.plist` untuk lokasi (GPS) dan kamera (face detection) sudah disiapkan
- [ ] Target awal distribusi iOS: TestFlight internal dulu

## 4. Rollback Plan

> Isi: kalau ada masalah kritis setelah live, apa langkah rollback-nya?
- Web: rollback deployment lewat dashboard Cloudflare Pages (pilih deployment sebelumnya → "Rollback"), atau redeploy versi lama lewat `wrangler` kalau pakai Worker
- Mobile: rilis versi baru

## 5. Setelah Live

- Catat versi rilis pertama di `CHANGELOG.md`
- Pantau error/crash (isi tool yang dipakai kalau ada, misal Firebase Crashlytics)
- Kumpulkan feedback pengguna awal (karyawan & admin) di minggu pertama
