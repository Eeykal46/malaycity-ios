// mc_elf_loader.h - Muatkan libGTASA.so (ELF arm64 Android) ke dalam app iOS.
//
// CARA HUSK: binari Android TIDAK diubah. Kita beri dia Android API di iOS.
// Ini berbeza sepenuhnya daripada "tukar ELF -> Mach-O":
//   - dyld tidak terlibat langsung
//   - kita mmap sendiri, copy segment, buat relocation sendiri
//   - kod Android jalan pada CPU sebenar (arm64 = arm64)
//   - setiap import Android (bionic, AAsset, OpenSL) dipenuhi oleh shim kita
//
// Apa yang perlu untuk libGTASA.so (diukur dari binari sebenar):
//   26,710 relocation : ABS64 10964, JUMP_SLOT 6335, RELATIVE 5252, GLOB_DAT 4159
//   274 import        : libc/STL 160, GL/EGL 74, POSIX 29, Android 6, OpenSL 5
//   152 init_array    : perlu dijalankan selepas relocation
//   x18               : 1394 arahan (iOS mengekalkan x18, jadi tiada masalah)
//
// Peringkat (seperti Husk: "find where the wall is"):
//   P1  mmap + copy segment + semak boleh baca
//   P2  relocation RELATIVE sahaja (tiada import) -> buktikan layout betul
//   P3  relocation GLOB_DAT/JUMP_SLOT melalui shim
//   P4  jalankan init_array
//   P5  panggil JNI_OnLoad
#ifndef MC_ELF_LOADER_H
#define MC_ELF_LOADER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool     ok;
    char     nota[512];
    void*    base;          // alamat asas dlm memori
    size_t   size;          // jumlah bait dipetakan
    int      segmen;        // bilangan PT_LOAD
    int      reloc_ok;      // bilangan relocation berjaya
    int      reloc_gagal;   // bilangan gagal
    int      import_ok;     // import dipenuhi oleh shim
    int      import_gagal;  // import tiada shim
    int      init_dijalan;  // init_array dijalankan
} McElfHasil;

/// Peringkat 1-2: petakan fail ELF ke memori dan buat relocation RELATIVE.
/// Tidak memanggil apa-apa kod daripada enjin.
McElfHasil mc_elf_petakan(const char* laluan);

/// Lepaskan memori yang dipetakan.
void mc_elf_lepas(McElfHasil* h);

#ifdef __cplusplus
}
#endif

#endif // MC_ELF_LOADER_H
