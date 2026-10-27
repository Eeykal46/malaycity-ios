// mc_ios_shim.mm - Pelaksanaan lapisan ganti Android -> iOS.
//
// Ini fail PALING PENTING dalam Fasa 3: di sinilah Android hilang dan iOS masuk.
//
// Semua yg di sini DISAHKAN perlu oleh ios/alat/analisis_elf.py:
//   libGTASA.so  -> AAssetManager_fromJava, AAssetManager_open, AAsset_close,
//                   AAsset_getLength, AAsset_read, __android_log_print
//   libOpenAL64  -> slCreateEngine, SL_IID_ENGINE, SL_IID_BUFFERQUEUE,
//                   SL_IID_ANDROIDSIMPLEBUFFERQUEUE, SL_IID_PLAY
//   bersama      -> EGL (ganti dgn EAGL), __system_property_get
//
// PENTING: shim ini TIDAK lengkap. Ia asas yang betul + ujian, bukan enjin
// penuh. Setiap fungsi di sini mesti diuji terhadap enjin sebenar sebelum
// boleh dipercayai.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <os/log.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#include "mc_ios_shim.h"

static char g_dataRoot[1024] = {0};
static os_log_t g_log = NULL;

// =====================================================================
//  1. Laluan fail  (Android: getExternalFilesDir -> iOS: Documents)
// =====================================================================
void mc_ios_init(const char* dataRoot) {
    if (dataRoot && dataRoot[0]) {
        strncpy(g_dataRoot, dataRoot, sizeof(g_dataRoot) - 1);
        g_dataRoot[sizeof(g_dataRoot) - 1] = 0;
    }
    if (!g_log) g_log = os_log_create("com.malaycity.ios.enjin", "default");
}

const char* mc_ios_data_root(void) { return g_dataRoot; }

// =====================================================================
//  2. AAsset  (Android asset manager) -> fail biasa dlm Documents
// =====================================================================
// Enjin Android membuka aset melalui AAssetManager. Di iOS kita letak fail
// yang sama dlm Documents, jadi AAsset jadi pembalut mmap/file biasa.

typedef struct {
    int      fd;
    void*    base;      // mmap atau malloc
    long     length;
    long     pos;
    int      mapped;
} MCAAsset;

void* AAssetManager_fromJava(void* env, void* assetManager) {
    // Android: JNIEnv + jobject. iOS: tiada asset manager - pulangkan penanda.
    return (void*)1;
}

void* AAssetManager_open(void* mgr, const char* filename, int mode) {
    if (!filename) return NULL;
    char path[2048];
    snprintf(path, sizeof(path), "%s/%s", g_dataRoot, filename);

    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        os_log_error(g_log, "AAssetManager_open: TIADA %{public}s", path);
        return NULL;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size <= 0) { close(fd); return NULL; }

    MCAAsset* a = (MCAAsset*)calloc(1, sizeof(MCAAsset));
    if (!a) { close(fd); return NULL; }
    a->fd = fd;
    a->length = (long)st.st_size;
    a->pos = 0;
    a->base = mmap(NULL, (size_t)a->length, PROT_READ, MAP_PRIVATE, fd, 0);
    a->mapped = (a->base != MAP_FAILED);
    if (!a->mapped) a->base = NULL;
    return a;
}

const void* AAsset_getBuffer(void* asset) {
    MCAAsset* a = (MCAAsset*)asset;
    return (a && a->mapped) ? a->base : NULL;
}

long AAsset_getLength(void* asset) {
    MCAAsset* a = (MCAAsset*)asset;
    return a ? a->length : 0;
}

long AAsset_getRemainingLength(void* asset) {
    MCAAsset* a = (MCAAsset*)asset;
    return a ? (a->length - a->pos) : 0;
}

int AAsset_read(void* asset, void* buf, size_t count) {
    MCAAsset* a = (MCAAsset*)asset;
    if (!a || !buf) return -1;
    if (a->mapped) {
        long n = a->length - a->pos;
        if ((long)count < n) n = (long)count;
        if (n <= 0) return 0;
        memcpy(buf, (const char*)a->base + a->pos, (size_t)n);
        a->pos += n;
        return (int)n;
    }
    ssize_t r = pread(a->fd, buf, count, a->pos);
    if (r > 0) a->pos += r;
    return (int)r;
}

long AAsset_seek(void* asset, long offset, int whence) {
    MCAAsset* a = (MCAAsset*)asset;
    if (!a) return -1;
    long np = a->pos;
    if (whence == SEEK_SET) np = offset;
    else if (whence == SEEK_CUR) np += offset;
    else if (whence == SEEK_END) np = a->length + offset;
    if (np < 0) np = 0;
    if (np > a->length) np = a->length;
    a->pos = np;
    return np;
}

void AAsset_close(void* asset) {
    MCAAsset* a = (MCAAsset*)asset;
    if (!a) return;
    if (a->mapped && a->base) munmap(a->base, (size_t)a->length);
    if (a->fd >= 0) close(a->fd);
    free(a);
}

// =====================================================================
//  3. Log  (Android: __android_log_print -> iOS: os_log)
// =====================================================================
int __android_log_print(int prio, const char* tag, const char* fmt, ...) {
    if (!g_log) g_log = os_log_create("com.malaycity.ios.enjin", "default");
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    os_log(g_log, "[%{public}s] %{public}s", tag ? tag : "?", buf);
    return (int)strlen(buf);
}

int __android_log_write(int prio, const char* tag, const char* text) {
    if (!g_log) g_log = os_log_create("com.malaycity.ios.enjin", "default");
    os_log(g_log, "[%{public}s] %{public}s", tag ? tag : "?", text ? text : "");
    return text ? (int)strlen(text) : 0;
}

int __android_log_vprint(int prio, const char* tag, const char* fmt, va_list ap) {
    if (!g_log) g_log = os_log_create("com.malaycity.ios.enjin", "default");
    char buf[2048];
    vsnprintf(buf, sizeof(buf), fmt, ap);
    os_log(g_log, "[%{public}s] %{public}s", tag ? tag : "?", buf);
    return (int)strlen(buf);
}

void __android_log_assert(const char* cond, const char* tag,
                          const char* fmt, ...) {
    if (!g_log) g_log = os_log_create("com.malaycity.ios.enjin", "default");
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    os_log_fault(g_log, "ASSERT [%{public}s] %{public}s (cond=%{public}s)",
                 tag ? tag : "?", buf, cond ? cond : "?");
    // Android abort di sini. Kita TIDAK abort: crash tanpa sebab jelas lebih
    // teruk drpd teruskan. Log sahaja - pemanggil boleh putuskan.
}

void android_set_abort_message(const char* msg) {
    if (!g_log) g_log = os_log_create("com.malaycity.ios.enjin", "default");
    os_log_fault(g_log, "abort message: %{public}s", msg ? msg : "");
}

// =====================================================================
//  4. System property  (Android sahaja) -> nilai tetap
// =====================================================================
// Enjin kadang semak ro.build.version.sdk / hardware GPU.
int __system_property_get(const char* name, char* value) {
    if (!value) return 0;
    value[0] = 0;
    if (!name) return 0;
    const char* v = "";
    if (strcmp(name, "ro.build.version.sdk") == 0)        v = "34";
    else if (strcmp(name, "ro.product.cpu.abi") == 0)     v = "arm64-v8a";
    else if (strcmp(name, "ro.product.model") == 0)       v = "iPhone";
    else if (strcmp(name, "ro.hardware") == 0)            v = "apple";
    strcpy(value, v);
    return (int)strlen(v);
}

// =====================================================================
//  5. OpenSL ES  (Android audio) -> AVAudioEngine
// =====================================================================
// Ini BUKAN implementasi OpenSL lengkap. Ia cukup supaya enjin boleh dimuat
// dan tidak crash; audio sebenar mesti ditulis kemudian (lihat TODO di bawah).
//
// TODO(audio): OBJ_ENGINE sebenar perlu AVAudioEngine + AVAudioPlayerNode.
// Sekarang: nilai pseudo supaya pautan berjaya dan laluan audio ditandakan.

typedef struct { int dummy; } MC_SLObject;

static MC_SLObject g_engineObj;
static MC_SLObject g_outputMixObj;
static MC_SLObject g_playerObj;
static MC_SLObject g_playItf;
static MC_SLObject g_bufferQueueItf;

// SL_IID_* ialah penuding kepada struktur ID. Enjin hanya bandingkan penuding,
// jadi kita beri alamat unik yang stabil.
static char g_iidEngine, g_iidPlay, g_iidBufferQueue, g_iidAndroidSimpleBufferQueue;
static char g_iidAndroidConfig, g_iidRecord;
// Dalam OpenSL ES sebenar, SL_IID_* ialah `const SLInterfaceID` (penuding ke
// struct const). Enjin hanya bandingkan penuding, jadi alamat unik mencukupi.
#define MC_SL_IID(name, var) static const void* const name = (const void*)&var
MC_SL_IID(SL_IID_ENGINE,                    g_iidEngine);
MC_SL_IID(SL_IID_PLAY,                      g_iidPlay);
MC_SL_IID(SL_IID_BUFFERQUEUE,               g_iidBufferQueue);
MC_SL_IID(SL_IID_ANDROIDSIMPLEBUFFERQUEUE,  g_iidAndroidSimpleBufferQueue);
MC_SL_IID(SL_IID_ANDROIDCONFIGURATION,      g_iidAndroidConfig);
MC_SL_IID(SL_IID_RECORD,                    g_iidRecord);

int slCreateEngine(void** pEngine, int numOptions, const void* pOptions,
                   int numInterfaces, const void* pInterfaceIds,
                   const void* pInterfaceRequired) {
    os_log(g_log, "slCreateEngine -> shim AVAudioEngine (belum berfungsi penuh)");
    if (pEngine) *pEngine = &g_engineObj;
    return 0;   // SL_RESULT_SUCCESS
}

