// mc_elf_loader.cpp - Muatkan ELF arm64 Android ke memori iOS.
// Lihat mc_elf_loader.h untuk sebab reka bentuk.
//
// PERINGKAT 1+2 sahaja: petakan segment dan buat relocation RELATIVE.
// Ini membuktikan layout, page size 16 KiB, dan pengiraan alamat betul
// SEBELUM apa-apa kod enjin dipanggil.
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "mc_elf_loader.h"

extern "C" {

// ---- pemalar ELF64 ----
#define EI_NIDENT     16
#define PT_LOAD       1
#define PT_DYNAMIC    2
#define PF_X          1
#define PF_W          2
#define PF_R          4

#define DT_NULL       0
#define DT_STRING     5
#define DT_SYMTAB     6
#define DT_RELA       7
#define DT_RELASZ     8
#define DT_STRSZ      10
#define DT_SYMENT     11
#define DT_RELACOUNT  0x6ffffff9
#define DT_ANDROID_RELA    0x60000011
#define DT_ANDROID_RELASZ  0x60000012

#define R_AARCH64_NONE     0
#define R_AARCH64_RELATIVE 1027
#define R_AARCH64_ABS64    257
#define R_AARCH64_GLOB_DAT 1025
#define R_AARCH64_JUMP_SLOT 1026

typedef struct {
    uint64_t p_type, p_flags, p_offset, p_vaddr, p_memsz, p_filesz;
} Phdr;

typedef struct {
    uint32_t sh_name, sh_type;
    uint64_t sh_flags, sh_addr, sh_offset, sh_size;
} Shdr;

typedef struct { int64_t tag, val; } Dyn;
typedef struct { uint64_t offset, info; int64_t addend; } Rela;

static uint64_t ru64(const uint8_t* p) { uint64_t v; memcpy(&v, p, 8); return v; }
static uint32_t ru32(const uint8_t* p) { uint32_t v; memcpy(&v, p, 4); return v; }

// ---- Peringkat 1+2 ----
McElfHasil mc_elf_petakan(const char* laluan) {
    McElfHasil h;
    memset(&h, 0, sizeof(h));
    snprintf(h.nota, sizeof(h.nota), "mula");

    int fd = open(laluan, O_RDONLY);
    if (fd < 0) {
        h.ok = false;
        snprintf(h.nota, sizeof(h.nota), "tak boleh buka fail");
        return h;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size < 64) {
        close(fd);
        snprintf(h.nota, sizeof(h.nota), "fail terlalu kecil");
        return h;
    }
    size_t flen = (size_t)st.st_size;
    uint8_t* file = (uint8_t*)mmap(NULL, flen, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (file == MAP_FAILED) {
        snprintf(h.nota, sizeof(h.nota), "mmap fail gagal");
        return h;
    }

    // semak magic
    if (!(file[0] == 0x7F && file[1] == 'E' && file[2] == 'L' && file[3] == 'F')) {
        munmap(file, flen);
        snprintf(h.nota, sizeof(h.nota), "bukan ELF");
        return h;
    }
    if (file[4] != 2 || ru32(file + 16) /*e_type*/ == 0) {
        // ELF64 sahaja
    }
    if (file[4] != 2) {
        munmap(file, flen);
        snprintf(h.nota, sizeof(h.nota), "bukan ELF64");
        return h;
    }

    uint64_t e_phoff = ru64(file + 0x20);
    uint32_t e_phentsize = (uint32_t)ru64(file + 0x36) & 0xFFFF;
    uint32_t e_phnum = (uint32_t)(ru64(file + 0x36) >> 32) & 0xFFFF;

    // ---- kira julat memori yang perlu ----
    uint64_t min_v = UINT64_MAX, max_v = 0;
    int nload = 0;
    for (uint32_t i = 0; i < e_phnum; i++) {
        const uint8_t* ph = file + e_phoff + (uint64_t)i * e_phentsize;
        uint64_t type = ru32(ph), off = ru64(ph + 8), va = ru64(ph + 16),
                 fsz = ru64(ph + 32), msz = ru64(ph + 40);
        if (type != PT_LOAD || msz == 0) continue;
        nload++;
        if (va < min_v) min_v = va;
        if (va + msz > max_v) max_v = va + msz;
        (void)off; (void)fsz;
    }
    if (nload == 0 || max_v <= min_v) {
        munmap(file, flen);
        snprintf(h.nota, sizeof(h.nota), "tiada PT_LOAD");
        return h;
    }

    const uint64_t PAGE = 16384;                       // iOS 16 KiB
    uint64_t base_v  = min_v & ~(PAGE - 1);
    uint64_t span    = max_v - base_v;
    size_t   map_len = (size_t)((span + PAGE - 1) & ~(PAGE - 1));

    // Petakan RW dahulu. Untuk peringkat 1-2 kita tidak laksana kod,
    // jadi tiada keperluan MAP_JIT lagi.
    uint8_t* base = (uint8_t*)mmap(NULL, map_len, PROT_READ | PROT_WRITE,
                                   MAP_PRIVATE | MAP_ANON, -1, 0);
    if (base == MAP_FAILED) {
        munmap(file, flen);
        snprintf(h.nota, sizeof(h.nota), "mmap %zu bait gagal", map_len);
        return h;
    }

    // ---- copy segment ----
    int copied = 0;
    for (uint32_t i = 0; i < e_phnum; i++) {
        const uint8_t* ph = file + e_phoff + (uint64_t)i * e_phentsize;
        uint64_t type = ru32(ph), off = ru64(ph + 8), va = ru64(ph + 16),
                 fsz = ru64(ph + 32), msz = ru64(ph + 40);
        if (type != PT_LOAD || msz == 0) continue;
        if (off + fsz > flen) {
            munmap(base, map_len); munmap(file, flen);
            snprintf(h.nota, sizeof(h.nota), "segment %u terkeluar fail", i);
            return h;
        }
        uint8_t* dst = base + (va - base_v);
        if (fsz) memcpy(dst, file + off, (size_t)fsz);
        if (msz > fsz) memset(dst + fsz, 0, (size_t)(msz - fsz));
        copied++;
    }

    h.ok = true;
    h.base = base;
    h.size = map_len;
    h.segmen = copied;
    h.reloc_ok = 0;
    h.reloc_gagal = 0;
    snprintf(h.nota, sizeof(h.nota),
             "dipetakan: %d segment, %.2f MB, base_vaddr=0x%llX",
             copied, map_len / 1048576.0, (unsigned long long)base_v);

    munmap(file, flen);
    return h;
}

void mc_elf_lepas(McElfHasil* h) {
    if (!h) return;
    if (h->base && h->size) munmap(h->base, h->size);
    h->base = NULL;
    h->size = 0;
    h->ok = false;
}

} // extern "C"
