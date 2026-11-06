# Project Island — User Manual

Panduan lengkap dari **clone repo** sampai aplikasi **otomatis berjalan saat MacBook dinyalakan**.

> Diuji untuk macOS 14+ (Sonoma / Sequoia) pada MacBook dengan notch (mis. MacBook Air M2). Pada monitor eksternal / Mac tanpa notch, aplikasi menampilkan "virtual island" di tepi atas layar.

---

## 1. Prasyarat

| Kebutuhan | Cara memasang | Cek |
|-----------|---------------|-----|
| Xcode Command Line Tools (Swift 5.9+) | `xcode-select --install` | `swift --version` |
| Rust toolchain | `brew install rust` atau https://rustup.rs | `cargo --version` |
| Git | Sudah ada bersama Command Line Tools | `git --version` |
| (Opsional) Spotify desktop | https://www.spotify.com/download | — |

Homebrew belum ada? Pasang dari https://brew.sh.

## 2. Clone repository

```bash
git clone https://github.com/<username>/<nama-repo>.git
cd <nama-repo>
```

Ganti `<username>/<nama-repo>` dengan URL repo GitHub Anda.

## 3. (Opsional) Verifikasi build

```bash
cargo test --workspace     # tes Rust (core, storage, bridge)
./scripts/test-macos.sh    # build app + tes integrasi Swift/UniFFI
```

Output akhir yang diharapkan: `PASS: All ... succeeded!`

## 4. Build aplikasi (.app)

```bash
./scripts/package-app.sh
```

Script ini akan: build Rust core → generate binding Swift → compile aplikasi → membuat bundle `build/Project Island.app` (dylib Rust dibundel di dalam app) → menandatangani secara ad-hoc.

Coba jalankan:

```bash
open "build/Project Island.app"
```

Island muncul di notch. Ikon menu bar (kanan atas) menyediakan *Toggle Island*, *Settings*, dan *Quit*.

## 5. Install & jalankan otomatis saat MacBook menyala

Cara tercepat (satu perintah):

```bash
./scripts/install-app.sh
```

Script ini akan:
1. Membangun aplikasi (langkah 4).
2. Menyalin ke `~/Applications/Project Island.app`.
3. Mendaftarkan **LaunchAgent** `~/Library/LaunchAgents/com.projectisland.macos.login.plist` agar app terbuka otomatis setiap Anda **login** ke macOS.
4. Menjalankan aplikasi sekarang.

Tanpa auto-start: `./scripts/install-app.sh --no-login-item`

### Alternatif manual (tanpa script)
1. Salin `build/Project Island.app` ke folder **Applications**.
2. Buka **System Settings → General → Login Items & Extensions**.
3. Di bagian *Open at Login*, klik **+**, pilih **Project Island**.

### Agar benar-benar jalan "saat MacBook dinyalakan"
macOS hanya dapat membuka aplikasi sesudah user login. Agar tidak perlu mengetik password:
**System Settings → Users & Groups → Automatically log in as…** → pilih akun Anda
(membutuhkan FileVault nonaktif; pertimbangkan risiko keamanannya).

Lalu uji dengan **Restart** — Island harus muncul sendiri setelah desktop tampil.

## 6. Izin macOS yang diminta

| Izin | Kapan muncul | Fungsi |
|------|--------------|--------|
| **Automation → Spotify / Music** | Pertama kali kontrol musik / baca lagu | Play/Pause, Next, Previous, seek, judul, artwork |
| **Network** (keluar) | Saat lagu berganti | Mengambil lirik dari LRCLIB & artwork Spotify |

Klik **OK / Allow**. Jika tidak sengaja menolak:
**System Settings → Privacy & Security → Automation** → aktifkan *Project Island → Spotify*.
Atau reset: `tccutil reset AppleEvents com.projectisland.macos` lalu buka ulang app.

Jika macOS memblokir app ("tidak dapat diverifikasi"): klik kanan app → **Open** → **Open**, atau
`xattr -dr com.apple.quarantine "~/Applications/Project Island.app"`.

## 7. Cara memakai

- **Hover** di notch → island membesar ke bawah; gerakkan kursor keluar → mengecil otomatis.
- **Klik** island saat collapsed → expand. Tombol **pin** menahan island tetap terbuka.
- **Tab:** Overview (Spotify + lirik live), Clipboard, Timer, Notes, Shelf, System.
- **Spotify:** tombol ⏮ ⏯ ⏭, klik bar progres untuk seek, tombol 💬 untuk menampilkan/menyembunyikan lirik. Saat collapsed, artwork berbentuk lingkaran dengan cincin progres lagu.
- **System:** CPU, RAM, baterai, disk — refresh otomatis tiap 2 detik.
- **Clipboard:** riwayat salinan (item password/rahasia otomatis diabaikan); klik item untuk menyalin ulang.
- **File Shelf:** seret file ke island untuk menyimpan sementara.

Data lokal tersimpan di `~/Library/Application Support/ProjectIsland/project_island.db`.

## 8. Update ke versi terbaru

```bash
cd <nama-repo>
git pull
./scripts/install-app.sh
```

## 9. Uninstall

```bash
./scripts/uninstall-app.sh               # hapus app + auto-start
./scripts/uninstall-app.sh --purge-data  # sekaligus hapus database lokal
```

## 10. Troubleshooting

| Gejala | Solusi |
|--------|--------|
| `cargo: command not found` | Pasang Rust (`brew install rust`), buka terminal baru |
| `swift: command not found` / error SDK | `xcode-select --install`, lalu `xcode-select -p` |
| Build gagal karena network (crates) | Jalankan sekali dengan internet agar dependensi Rust terunduh |
| Island tidak muncul | Cek ikon di menu bar → *Toggle Island*; pastikan app berjalan: `pgrep -fl ProjectIslandApp` |
| Tombol Spotify tidak bereaksi | Pastikan Spotify sedang terbuka & izin Automation aktif (bagian 6) |
| Lirik tidak muncul | Perlu koneksi internet; tidak semua lagu punya lirik tersinkron di LRCLIB |
| Tidak jalan setelah restart | `launchctl list \| grep projectisland`; jalankan ulang `./scripts/install-app.sh`; cek log: `log show --last 5m --predicate 'process == "ProjectIslandApp"'` |
| Dipindah/hapus folder repo | Aman — dylib Rust sudah ada di dalam `.app` |
