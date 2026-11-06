# Project Island — Panduan Instalasi & Pemindahan ke Applications

Dokumen ini menyediakan panduan lengkap untuk membangun (*compile/build*), menginstal, memindahkan, dan mengoperasikan **Project Island** sebagai aplikasi macOS native (`.app`) di folder `/Applications` tanpa harus menjalankannya melalui Terminal.

---

## Daftar Isi
1. [Prasyarat Sistem](#1-prasyarat-sistem)
2. [Membangun Aplikasi (Build Configuration)](#2-membangun-aplikasi-build-configuration)
   - [Development Build (Debug)](#development-build-debug)
   - [Production/Distribution Build (Release)](#productiondistribution-build-release)
3. [Struktur & Lokasi Hasil Build `.app`](#3-struktur--lokasi-hasil-build-app)
4. [Memindahkan ke `/Applications`](#4-memindahkan-ke-applications)
   - [Metode 1: Menggunakan Skrip Otomatis (Direkomendasikan)](#metode-1-menggunakan-skrip-otomatis-direkomendasikan)
   - [Metode 2: Menggunakan Finder](#metode-2-menggunakan-finder)
   - [Metode 3: Menggunakan Command Line (Terminal)](#metode-3-menggunakan-command-line-terminal)
5. [Menjalankan Aplikasi](#5-menjalankan-aplikasi)
6. [Mengatur Auto-Start Saat Login (Launch at Login)](#6-mengatur-auto-start-saat-login-launch-at-login)
7. [Izin macOS & Penanganan Gatekeeper](#7-izin-macos--penanganan-gatekeeper)
   - [Gatekeeper & Karantina macOS](#gatekeeper--karantina-macos)
   - [Izin Apple Events / Automation (Spotify & Music)](#izin-apple-events--automation-spotify--music)
   - [Izin Notifikasi](#izin-notifikasi)
   - [Izin Aksesibilitas (Opsional)](#izin-aksesibilitas-opsional)
8. [Memperbarui Aplikasi ke Versi Baru](#8-memperbarui-aplikasi-ke-versi-baru)
9. [Penjelasan Distribusi Luas (Developer ID & Notarization)](#9-penjelasan-distribusi-luas-developer-id--notarization)
10. [Cara Menghapus Aplikasi (Uninstall)](#10-cara-menghapus-aplikasi-uninstall)
11. [Troubleshooting & Solusi Masalah](#11-troubleshooting--solusi-masalah)

---

## 1. Prasyarat Sistem

- **Sistem Operasi:** macOS Sonoma (14.0) atau macOS Sequoia (15.0+).
- **Perangkat Keras:** MacBook Air M2 / Apple Silicon Mac (didukung penuh) atau Mac berbasis Intel.
- **Toolchain Pengembangan (hanya jika membangun dari source):**
  - Xcode Command Line Tools: `xcode-select --install`
  - Rust & Cargo (1.78+): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
  - Swift Toolchain: terpasang bawaan bersama Xcode / Command Line Tools.

---

## 2. Membangun Aplikasi (Build Configuration)

Project Island memisahkan proses kompilasi antara **Development (Debug)** dan **Production (Release)**.

### Production/Distribution Build (Release) — Direkomendasikan untuk Penggunaan Sehari-hari
Build Release mengaktifkan optimasi biner penuh dari rustc (`opt-level = 3`, LTO) dan Swift compiler (`-c release`), menghasilkan binary yang jauh lebih kecil, hemat memori, dan responsif.

Jalankan perintah berikut di direktori root repositori:

```bash
./scripts/package-app.sh --release
```

**Apa yang dilakukan skrip ini secara otomatis?**
1. Membangun core Rust (`island-bridge`) dengan flag `--release`.
2. Menghasilkan binding Swift UniFFI dan header C terbaru.
3. Mengompilasi binary Swift `ProjectIslandApp` dengan konfigurasi `-c release`.
4. Merangkai struktur bundle macOS `.app` lengkap di `build/Project Island.app`.
5. Menyalin dylib dinamis Rust (`libisland_bridge.dylib`) ke dalam `Contents/Frameworks/` dan memperbaiki ID runtime `@rpath` dengan `install_name_tool`.
6. Memasukkan `Info.plist` dan entitlements yang valid.
7. Menandatangani bundle secara lokal (*ad-hoc code signing*).

### Development Build (Debug)
Untuk kebutuhan pengujian dan debugging:

```bash
./scripts/package-app.sh
```

Hasil build debug berada di lokasi yang sama (`build/Project Island.app`), tetapi menggunakan binary debug yang menyertakan simbol debug tanpa optimasi LTO.

---

## 3. Struktur & Lokasi Hasil Build `.app`

Hasil packaging selalu berada di direktori:
```
<repo-root>/build/Project Island.app
```

Struktur internal bundle yang valid:
```
Project Island.app/
├── Contents/
│   ├── Info.plist               # Bundle identifier, versioning, strings izin
│   ├── MacOS/
│   │   └── ProjectIslandApp     # Executable biner native Swift
│   ├── Frameworks/
│   │   └── libisland_bridge.dylib # Rust core engine & SQLite database runtime
│   └── Resources/               # Aset grafis & ikon
```

Bundle ini mandiri (*self-contained*), artinya dapat dipindahkan ke direktori mana pun di macOS tanpa ketergantungan pada path folder tempat Anda meng-clone repositori.

---

## 4. Memindahkan ke `/Applications`

### Metode 1: Menggunakan Skrip Otomatis (Direkomendasikan)
Skrip `install-app.sh` secara otomatis membangun versi Release, menyalin aplikasi ke `/Applications`, membersihkan atribut karantina, dan mendaftarkan aplikasi agar aktif saat MacBook dinyalakan:

```bash
./scripts/install-app.sh --release
```

Jika akun pengguna Anda tidak memiliki hak tulis langsung ke `/Applications` tanpa `sudo`, skrip akan otomatis memasangnya ke `~/Applications` (folder Applications milik akun Anda). Jika Anda ingin memaksakan instalasi ke `/Applications` sistem, gunakan:

```bash
sudo ./scripts/install-app.sh --release --system
```

### Metode 2: Menggunakan Finder
1. Buka folder `build/` di repositori menggunakan Finder:
   ```bash
   open build/
   ```
2. Tarik (*drag-and-drop*) file **Project Island.app** ke folder **Applications** di sidebar Finder Anda.
3. Jika muncul permintaan otentikasi, masukkan kata sandi atau Touch ID Mac Anda.

### Metode 3: Menggunakan Command Line (Terminal)
Jika Anda lebih menyukai perintah terminal manual:

```bash
# 1. Hentikan aplikasi jika sedang berjalan
pkill -f "Project Island.app/Contents/MacOS/ProjectIslandApp" 2>/dev/null || true

# 2. Salin bundle ke /Applications
cp -R "build/Project Island.app" /Applications/

# 3. Hapus atribut karantina Gatekeeper pada bundle lokal
xattr -dr com.apple.quarantine "/Applications/Project Island.app" 2>/dev/null || true
```

---

## 5. Menjalankan Aplikasi

Setelah berada di `/Applications`, Anda dapat membuka aplikasi seperti aplikasi macOS resmi lainnya:

1. **Spotlight:** Tekan `Cmd + Space`, ketik `Project Island`, lalu tekan `Enter`.
2. **Launchpad:** Buka Launchpad, klik ikon **Project Island**.
3. **Finder:** Buka `/Applications` dan klik ganda pada **Project Island.app**.
4. **Menu Bar:** Project Island akan muncul di status bar atas (ikon notch) dan mengaitkan floating window ke notch fisik MacBook Air M2 Anda.

---

## 6. Mengatur Auto-Start Saat Login (Launch at Login)

Agar Project Island otomatis berjalan setiap kali Mac dinyalakan atau login:

### Cara A: Melalui macOS System Settings (GUI)
1. Buka **System Settings** di Mac.
2. Pilih menu **General** > **Login Items**.
3. Pada bagian **Open at Login**, klik tombol **+** (tambah).
4. Navigasi ke `/Applications`, pilih **Project Island**, lalu klik **Open**.

### Cara B: Melalui LaunchAgent (Terminal)
Jika Anda menggunakan `./scripts/install-app.sh`, LaunchAgent telah dikonfigurasi secara otomatis di `~/Library/LaunchAgents/com.projectisland.macos.login.plist`.

---

## 7. Izin macOS & Penanganan Gatekeeper

### Gatekeeper & Karantina macOS
Karena aplikasi dibangun langsung dari source code lokal dan ditandatangani secara *ad-hoc* (tanpa Apple Developer Team ID berbayar), macOS mungkin menampilkan dialog:
> *"Project Island" cannot be opened because the developer cannot be verified.*

**Cara membuka yang benar (Standar Apple, tanpa mematikan Gatekeeper):**
1. Buka **System Settings** > **Privacy & Security**.
2. Gulir ke bawah hingga menemukan bagian **Security**.
3. Anda akan melihat pesan: *"Project Island was blocked from use because it is not from an identified developer"*.
4. Klik tombol **Open Anyway** dan masukkan password/Touch ID Anda.
5. Atau dari Terminal, bersihkan atribut karantina pada aplikasi yang telah dipindahkan:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Project Island.app"
   ```

> [!CAUTION]
> Jangan pernah mematikan Gatekeeper secara global (`sudo spctl --master-disable`) karena dapat membahayakan keamanan sistem Mac Anda dari malware eksternal.

### Izin Apple Events / Automation (Spotify & Music)
Saat pertama kali Project Island mendeteksi playback Spotify, macOS akan menampilkan dialog izin:
> *"Project Island wants to control Spotify to access now playing track and playback controls."*

Pilih **OK** / **Allow**.

Jika tidak sengaja ditolak:
1. Buka **System Settings** > **Privacy & Security** > **Automation**.
2. Cari **Project Island** dan centang **Spotify** serta **Music**.

### Izin Notifikasi
Saat timer selesai, Project Island akan mengirimkan notifikasi native. Izinkan banner notifikasi saat prompt pertama muncul.

---

## 8. Memperbarui Aplikasi ke Versi Baru

Ketika Anda memperbarui kode sumber (`git pull`), ikuti langkah ini untuk memperbarui aplikasi yang terpasang di `/Applications`:

```bash
# 1. Update source code
git pull

# 2. Re-build dan install versi release terbaru
./scripts/install-app.sh --release
```

Aplikasi yang lama akan otomatis dihentikan dan digantikan dengan versi baru tanpa menghapus data riwayat clipboard, catatan, atau pengaturan Anda.

---

## 9. Penjelasan Distribusi Luas (Developer ID & Notarization)

Jika Anda berniat mendistribusikan Project Island ke pengguna lain tanpa mereka harus melakukan kompilasi dari source code:

1. **Apple Developer Program:** Memerlukan akun berbayar ($99/tahun) dari Apple.
2. **Developer ID Application Certificate:** Digunakan untuk menandatangani biner:
   ```bash
   codesign --deep --force --options runtime --sign "Developer ID Application: Your Name (TEAM_ID)" "Project Island.app"
   ```
3. **Apple Notarization Service:** Kirim biner ke Apple Notary Service menggunakan `notarytool`:
   ```bash
   xcrun notarytool submit "Project Island.zip" --keychain-profile "AC_PASSWORD" --wait
   xcrun stapler staple "Project Island.app"
   ```
Setelah di-staple, aplikasi dapat diunduh oleh siapa saja dan dibuka langsung di macOS tanpa peringatan Gatekeeper.

Untuk penggunaan pribadi di Mac Anda sendiri, penandatanganan *ad-hoc* bawaan skrip packaging (`--sign -`) sudah sepenuhnya cukup dan aman.

---

## 10. Cara Menghapus Aplikasi (Uninstall)

Untuk menghapus aplikasi dan semua konfigurasinya secara bersih:

```bash
# Hapus aplikasi dan launch agent:
./scripts/uninstall-app.sh

# Atau jika ingin menghapus seluruh database riwayat clipboard & preferensi:
./scripts/uninstall-app.sh --purge-data
```

Jika menghapus secara manual:
1. Pindahkan `/Applications/Project Island.app` ke Trash.
2. Hapus `~/Library/LaunchAgents/com.projectisland.macos.login.plist` jika ada.
3. (Opsional) Hapus folder database di `~/Library/Application Support/ProjectIsland`.

---

## 11. Troubleshooting & Solusi Masalah

| Masalah | Penyebab | Solusi |
| :--- | :--- | :--- |
| **Aplikasi langsung crash saat dibuka dari `/Applications`** | Ketergantungan dylib `libisland_bridge.dylib` tidak ditemukan atau path rpath rusak. | Pastikan menggunakan `./scripts/package-app.sh --release` yang otomatis mengemas dylib ke `Contents/Frameworks/` dengan `@executable_path/../Frameworks/`. |
| **"Project Island is damaged and cannot be opened"** | Gatekeeper menandai biner dengan flag karantina setelah disalin. | Jalankan `xattr -cr "/Applications/Project Island.app"` di Terminal. |
| **Kontrol Spotify tidak merespons** | Izin Apple Events belum diberikan atau ditolak. | Buka **System Settings** > **Privacy & Security** > **Automation**, aktifkan izin untuk Spotify di bawah Project Island. |
| **Aplikasi tidak muncul di notch** | Mode tampilan tersembunyi atau status item menu bar dinonaktifkan. | Klik ikon Project Island di Menu Bar kanan atas, lalu pilih **Reset Island Window**. |
| **Database terkunci (*database locked*)** | Ada instance lama yang masih berjalan di latar belakang. | Jalankan `pkill -f ProjectIslandApp` lalu buka kembali aplikasi. |
