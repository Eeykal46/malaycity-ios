/* Paksa linker KEKALKAN simbol Husk.
 *
 * MASALAH: McHusk.swift guna dlsym(). Kerana tiada rujukan langsung kepada
 * husk_tl_*, linker menganggap kod itu "dead code" dan membuangnya.
 * Hasilnya dlsym() pulangkan NULL -> "API dilink : TIDAK".
 *
 * PENYELESAIAN: ambil ALAMAT setiap fungsi di sini. Rujukan alamat tidak
 * boleh dioptimum keluar, jadi linker wajib kekalkan simbol.
 */
#include "husk-tl.h"

int mc_husk_tersedia(void) {
    /* volatile: halang pengoptimum daripada buang perbandingan ini */
    void *volatile a = (void *)husk_tl_scan;
    void *volatile b = (void *)husk_tl_attempt_start;
    void *volatile c = (void *)husk_tl_run_checks;
    void *volatile d = (void *)husk_tl_frame_acquire;
    (void)a; (void)b; (void)c; (void)d;
    return (a && b) ? 1 : 0;
}

/* Pulang 1 jika semua API penting wujud (dipanggil dari Swift sebagai ujian). */
int mc_husk_semak_api(void) {
    return (husk_tl_scan
         && husk_tl_run_checks
         && husk_tl_attempt_start
         && husk_tl_attempt_done
         && husk_tl_attempt_frames
         && husk_tl_attempt_log
         && husk_tl_attempt_stop
         && husk_tl_attempt_reset
         && husk_tl_frame_acquire
         && husk_tl_frame_release
         && husk_tl_send_touch
         && husk_tl_free) ? 1 : 0;
}
