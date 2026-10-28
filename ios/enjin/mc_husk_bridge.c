/* Paksa linker KEKALKAN simbol Husk.
 *
 * MASALAH: Swift memanggil tl_gta_* melalui rujukan langsung, tetapi jika
 * tiada rujukan dari C, linker boleh buang kod sebagai dead code.
 * Penyelesaian: ambil ALAMAT fungsi di sini.
 */
#include "husk-tl-gtasa.h"
#include "husk-tl-gameactivity.h"

int mc_husk_semak_api(void) {
    void *volatile a = (void *)tl_gta_start;
    void *volatile b = (void *)tl_gta_run;
    void *volatile c = (void *)tl_gta_touch;
    void *volatile d = (void *)tl_ga_start;
    void *volatile e = (void *)tl_ga_frames;
    (void)a; (void)b; (void)c; (void)d; (void)e;
    return (a && b && c) ? 1 : 0;
}
