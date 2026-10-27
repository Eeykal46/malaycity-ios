// mc_ios_shim.h - Lapisan ganti Android -> iOS untuk libGTASA/libSCAnd/libOpenAL.
//
// LATAR: ujian GLProbe di iPhone 13 Pro (28 Okt 2026) SAHKAN OpenGL ES 2.0
// berfungsi pada iOS 26 (GL_VERSION = "OpenGL ES 2.0 Metal - 105", render
// segi tiga BERJAYA, PVRTC ADA). Jadi kita TIDAK perlu tulis backend Metal.
//
// Yang tinggal ialah menggantikan panggilan khusus Android. Analisis ELF
// (ios/alat/analisis_elf.py) menunjukkan jumlahnya KECIL:
//   libGTASA.so  : AAsset x4, __android_log_print, __system_property*(?)
//   libSCAnd.so  : 4 Android khas
//   libOpenAL64  : 2 Android khas + 6 OpenSL ES
// Jumlah: 17 fungsi.
//
// Carta pemetaan:
//   EGL*              -> EAGL/EAGLContext (Apple)          [GLES 2.0]
//   AAsset*           -> NSBundle/NSFileHandle + mmap
//   __android_log_*   -> os_log / fprintf(stderr)
//   __system_property_get -> pembolehubah tetap
//   slCreateEngine    -> AVAudioEngine / AudioQueue
//   ANativeWindow_*   -> UIView/CAEAGLLayer
//
#ifndef MC_IOS_SHIM_H
#define MC_IOS_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

// Panggil SEKALI sebelum apa-apa inisiatif enjin. Menetapkan EAGLContext
// semasa dan menyediakan laluan fail (Documents).
void mc_ios_init(const char* dataRoot);

// Laluan folder data (Documents) - ganti getExternalFilesDir().
const char* mc_ios_data_root(void);

#ifdef __cplusplus
}
#endif

#endif // MC_IOS_SHIM_H
