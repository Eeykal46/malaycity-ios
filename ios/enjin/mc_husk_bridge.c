/* Paksa linker KEKALKAN simbol Husk + sediakan fungsi yang Husk hanya
 * ISYTIHAR tetapi tidak beri pelaksanaan.
 *
 * MASALAH: Swift memanggil tl_gta_* melalui rujukan langsung, tetapi jika
 * tiada rujukan dari C, linker boleh buang kod sebagai dead code.
 * Penyelesaian: ambil ALAMAT fungsi di sini.
 *
 * tl_log_line: 40+ fail Husk memanggilnya tetapi tiada .c yang mentakrifkannya
 * (ia disediakan oleh host Husk). Kita beri pelaksanaan mudah -> os_log.
 */
#include <stdarg.h>
#include <stdio.h>
#include <os/log.h>

#include "husk-tl-gtasa.h"
#include "husk-tl-gameactivity.h"

/* Satu-satunya takrif tl_log_line dlm projek ini. */
void tl_log_line(const char *fmt, ...) {
    static os_log_t log_ = NULL;
    if (!log_) log_ = os_log_create("com.malaycity.ios.husk", "tl");
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    os_log(log_, "%{public}s", buf);
}

/* tl_find_stikdebug_prewarmed: husk-tl-xmem.c memanggilnya tetapi tiada
 * takrifan dalam source awam Husk 3.1 (ia disediakan oleh host Husk yang
 * berkait dengan StikJIT). Kita pulangkan NULL = "tiada pramuat", dan
 * husk-tl-xmem.c jatuh ke laluan MAP_JIT biasa. Itu laluan yang sah.
 */
struct tl_dual_mapping;
struct tl_dual_mapping *tl_find_stikdebug_prewarmed(void) {
    return (struct tl_dual_mapping *)0;
}

int mc_husk_semak_api(void) {
    void *volatile a = (void *)tl_gta_start;
    void *volatile b = (void *)tl_gta_run;
    void *volatile c = (void *)tl_gta_touch;
    void *volatile d = (void *)tl_ga_start;
    void *volatile e = (void *)tl_ga_frames;
    (void)a; (void)b; (void)c; (void)d; (void)e;
    return (a && b && c) ? 1 : 0;
}
