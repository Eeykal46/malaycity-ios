import UIKit
import OpenGLES

/// UJIAN ANDAIAN PALING KRITIKAL DALAM SELURUH PROJEK.
///
/// Soalan: boleh tak iOS 26 masih cipta konteks OpenGL ES dan render?
///
/// Sebelum ini aku andaikan "iOS tiada GLES, mesti tulis Metal". Itu ANDAIAN,
/// bukan ukuran. Kalau ujian ini LULUS, 74 panggilan GL/EGL dalam libGTASA.so
/// TIDAK perlu lapisan Metal, dan Fasa 3 menjadi jauh lebih kecil.
///
/// Ujian buat kerja sebenar: cipta konteks, kompil shader, render segi tiga
/// ke framebuffer, baca balik piksel. Bukan sekadar semak API wujud.
final class GLProbe {

    struct Result {
        var ok = false
        var version = ""
        var renderer = ""
        var vendor = ""
        var glsl = ""
        var pvrtc = false
        var etc1 = false
        var s3tc = false
        var gl3 = false
        var triangleRendered = false
        var pixel: (r: UInt8, g: UInt8, b: UInt8) = (0, 0, 0)
        var notes: [String] = []
    }

    static func run() -> Result {
        var r = Result()

        guard let ctx = EAGLContext(api: .openGLES2) else {
            r.notes.append("EAGLContext(.openGLES2) GAGAL dicipta")
            return r
        }
        guard EAGLContext.setCurrent(ctx) else {
            r.notes.append("setCurrent GAGAL")
            return r
        }
        r.ok = true
        r.version = str(GL_VERSION)
        r.renderer = str(GL_RENDERER)
        r.vendor = str(GL_VENDOR)
        r.glsl = str(GL_SHADING_LANGUAGE_VERSION)

        let ext = r.version.isEmpty ? "" : str(GL_EXTENSIONS)
        r.pvrtc = ext.contains("GL_IMG_texture_compression_pvrtc")
        r.etc1 = ext.contains("GL_OES_compressed_ETC1_RGB8_texture")
        r.s3tc = ext.contains("GL_EXT_texture_compression_s3tc")
            || ext.contains("GL_EXT_texture_compression_dxt1")

        r.triangleRendered = renderTriangle(&r)

        if let ctx3 = EAGLContext(api: .openGLES3) {
            r.gl3 = true
            _ = EAGLContext.setCurrent(ctx3)
            r.notes.append("GLES3 context: ADA")
        } else {
            r.notes.append("GLES3 context: TIADA")
        }
        return r
    }

    private static func str(_ name: Int32) -> String {
        guard let p = glGetString(GLenum(name)) else { return "" }
        return String(cString: p)
    }

    /// Cipta framebuffer 64x64, kompil shader, render segi tiga merah, baca piksel.
    /// Ini ujian SEBENAR - bukan semak API wujud.
    private static func renderTriangle(_ r: inout Result) -> Bool {
        let W: Int32 = 64, H: Int32 = 64

        var fbo: GLuint = 0, tex: GLuint = 0, rbo: GLuint = 0
        glGenFramebuffers(1, &fbo)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)

        glGenTextures(1, &tex)
        glBindTexture(GLenum(GL_TEXTURE_2D), tex)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, W, H, 0,
                     GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_2D), tex, 0)

        glGenRenderbuffers(1, &rbo)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), rbo)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_DEPTH_COMPONENT16), W, H)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_ATTACHMENT),
                                  GLenum(GL_RENDERBUFFER), rbo)

        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        guard status == GLenum(GL_FRAMEBUFFER_COMPLETE) else {
            r.notes.append("Framebuffer tak lengkap: 0x\(String(status, radix: 16))")
            return false
        }

        let vsSrc = "attribute vec2 pos; void main(){ gl_Position = vec4(pos,0.0,1.0); }"
        let fsSrc = "precision mediump float; void main(){ gl_FragColor = vec4(1.0,0.0,0.0,1.0); }"
        guard let prog = buildProgram(vsSrc, fsSrc) else {
            r.notes.append("Kompil shader GAGAL")
            return false
        }
        glUseProgram(prog)

        let verts: [GLfloat] = [-1, -1, 3, -1, -1, 3]
        var vbo: GLuint = 0
        glGenBuffers(1, &vbo)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        verts.withUnsafeBufferPointer { p in
            glBufferData(GLenum(GL_ARRAY_BUFFER),
                         p.count * MemoryLayout<GLfloat>.size,
                         p.baseAddress, GLenum(GL_STATIC_DRAW))
        }
        let loc = glGetAttribLocation(prog, "pos")
        glEnableVertexAttribArray(GLuint(loc))
        glVertexAttribPointer(GLuint(loc), 2, GLenum(GL_FLOAT),
                              GLboolean(GL_FALSE), 0, nil)

        glViewport(0, 0, W, H)
        glClearColor(0, 0, 1, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        glDrawArrays(GLenum(GL_TRIANGLES), 0, 3)

        var px = [UInt8](repeating: 0, count: 4)
        glReadPixels(W / 2, H / 2, 1, 1, GLenum(GL_RGBA),
                     GLenum(GL_UNSIGNED_BYTE), &px)

        glDeleteBuffers(1, &vbo)
        glDeleteProgram(prog)
        glDeleteFramebuffers(1, &fbo)
        glDeleteRenderbuffers(1, &rbo)
        glDeleteTextures(1, &tex)

        r.pixel = (px[0], px[1], px[2])
        let merah = px[0] > 200 && px[1] < 60 && px[2] < 60
        if !merah {
            r.notes.append("Piksel tengah = (\(px[0]),\(px[1]),\(px[2])) bukan merah")
        }
        return merah
    }

    private static func buildProgram(_ vs: String, _ fs: String) -> GLuint? {
        func compile(_ src: String, _ type: GLenum) -> GLuint? {
            let s = glCreateShader(type)
            src.withCString { c in
                var p: UnsafePointer<GLchar>? = c
                glShaderSource(s, 1, &p, nil)
            }
            glCompileShader(s)
            var ok: GLint = 0
            glGetShaderiv(s, GLenum(GL_COMPILE_STATUS), &ok)
            return ok == GL_TRUE ? s : nil
        }
        guard let v = compile(vs, GLenum(GL_VERTEX_SHADER)),
              let f = compile(fs, GLenum(GL_FRAGMENT_SHADER)) else { return nil }
        let p = glCreateProgram()
        glAttachShader(p, v)
        glAttachShader(p, f)
        glLinkProgram(p)
        var ok: GLint = 0
        glGetProgramiv(p, GLenum(GL_LINK_STATUS), &ok)
        glDeleteShader(v)
        glDeleteShader(f)
        return ok == GL_TRUE ? p : nil
    }

    static func report(_ r: Result) -> String {
        var s = "=== UJIAN OPENGL ES DI IOS ===\n"
        s += "konteks dicipta : \(r.ok ? "YA" : "TIDAK")\n"
        s += "GL_VERSION      : \(r.version)\n"
        s += "GL_RENDERER     : \(r.renderer)\n"
        s += "GL_VENDOR       : \(r.vendor)\n"
        s += "GLSL            : \(r.glsl)\n"
        s += "GLES3 context   : \(r.gl3 ? "ADA" : "TIADA")\n"
        s += "sambungan PVRTC : \(r.pvrtc ? "ADA" : "TIADA")\n"
        s += "sambungan ETC1  : \(r.etc1 ? "ADA" : "TIADA")\n"
        s += "sambungan S3TC  : \(r.s3tc ? "ADA" : "TIADA")\n"
        s += "shader kompil   : \(r.triangleRendered ? "YA" : "TIDAK")\n"
        s += "render segi tiga: \(r.triangleRendered ? "BERJAYA" : "GAGAL")\n"
        s += "piksel tengah   : R=\(r.pixel.r) G=\(r.pixel.g) B=\(r.pixel.b)\n"
        if !r.notes.isEmpty {
            s += "nota:\n"
            for n in r.notes { s += "  - \(n)\n" }
        }
        s += r.triangleRendered
            ? "KESIMPULAN: GLES BERFUNGSI -> libGTASA mungkin boleh guna terus.\n"
            : "KESIMPULAN: GLES TIDAK berfungsi penuh -> perlu lapisan Metal.\n"
        return s
    }
}

