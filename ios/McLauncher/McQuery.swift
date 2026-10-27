import Foundation
import Darwin

/// Pertanyaan server SA-MP (paket 'i'): pemain, had, nama, ping.
/// Cermin `McQuery.java` - format paket SAMA (SA-MP 0.3.7).
enum McQuery {

    /// Blok sehingga timeoutMs*2 (2 cubaan). Panggil di thread latar.
    static func query(host: String, port: Int, timeoutMs: Int) -> [String: Any] {
        var out: [String: Any] = ["online": false]
        guard !host.isEmpty else { return out }

        // IPv4 sahaja: server SA-MP dengar UDP IPv4 (sama macam McQuery.java).
        let v4 = resolveIPv4(host)
        guard let ip = v4 else { return out }

        for _ in 0..<2 {
            let sock = socket(AF_INET, SOCK_DGRAM, 0)
            if sock < 0 { continue }
            // defer dlm badan `for` berjalan di akhir SETIAP iterasi (badan loop = skop sendiri),
            // jadi soket ditutup setiap pusingan - termasuk bila `continue`.
            defer { close(sock) }

            var tv = timeval(tv_sec: timeoutMs / 1000, tv_usec: (timeoutMs % 1000) * 1000)
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            // pakej: "SAMP" + ip[4] + port(2, little endian) + 'i'
            var pkt = [UInt8](repeating: 0, count: 11)
            pkt[0] = 0x53; pkt[1] = 0x41; pkt[2] = 0x4D; pkt[3] = 0x50
            // Ambil 4 bait alamat secara eksplisit: `withUnsafeBytes(of: in_addr)` boleh
            // menyertakan padding struct, jadi jangan salin `raw[i]` tanpa semak saiz.
            let be = UInt32(bigEndian: ip.s_addr)
            pkt[4] = UInt8((be >> 24) & 0xFF)
            pkt[5] = UInt8((be >> 16) & 0xFF)
            pkt[6] = UInt8((be >> 8) & 0xFF)
            pkt[7] = UInt8(be & 0xFF)
            pkt[8] = UInt8(port & 0xFF)
            pkt[9] = UInt8((port >> 8) & 0xFF)
            pkt[10] = 0x69                                   // 'i'

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)   // Darwin perlukan ini
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(UInt16(port).bigEndian)
            addr.sin_addr = ip

            let t0 = DispatchTime.now().uptimeNanoseconds
            let sent = withUnsafePointer(to: &addr) { ap -> Int in
                ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    pkt.withUnsafeBufferPointer { bp in
                        sendto(sock, bp.baseAddress, bp.count, 0, sp, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if sent <= 0 { continue }

            var buf = [UInt8](repeating: 0, count: 2048)
            var from = sockaddr_in()
            from.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) { fp -> Int in
                fp.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                    buf.withUnsafeMutableBufferPointer { bp in
                        recvfrom(sock, bp.baseAddress, bp.count, 0, sp, &fromLen)
                    }
                }
            }
            let pingMs = Int((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            if n < 11 + 1 + 2 + 2 + 4 { continue }
            if buf[10] != 0x69 { continue }

            var o = 11
            let pass = buf[o]; o += 1
            // Semua baca guna Int (64-bit di iOS) -> tiada overflow, tiada trap.
            let players = Int(buf[o]) | (Int(buf[o + 1]) << 8); o += 2
            let maxPlayers = Int(buf[o]) | (Int(buf[o + 1]) << 8); o += 2
            let hl = Int(buf[o]) | (Int(buf[o + 1]) << 8) | (Int(buf[o + 2]) << 16) | (Int(buf[o + 3]) << 24)
            o += 4
            var hostname = ""
            if hl > 0 && o + hl <= n {
                // windows-1252 = sama macam McQuery.java; utf8 dulu (server moden hantar utf8)
                let bytes = Data(buf[o..<(o + hl)])
                if let utf8 = String(data: bytes, encoding: .utf8) {
                    hostname = utf8
                } else {
                    hostname = String(data: bytes, encoding: McQuery.cp1252) ?? ""
                }
            }
            out["online"] = true
            out["players"] = players
            out["max"] = maxPlayers
            out["ping"] = pingMs
            out["hostname"] = hostname
            out["password"] = pass != 0
            return out
        }
        return out
    }

    // MARK: - pengekodan nama

    /// windows-1252 (CP1252) - sama macam `Charset.forName("windows-1252")` dlm McQuery.java.
    static let cp1252: String.Encoding = {
        let cf = CFStringConvertWindowsCodepageToEncoding(1252)
        if cf != kCFStringEncodingInvalidId {
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
        return .isoLatin1
    }()

    /// Alamat IPv4 pertama bagi host (sokong nama domain & IP terus).
    private static func resolveIPv4(_ host: String) -> in_addr? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var res: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, nil, &hints, &res)
        guard rc == 0, let first = res else {
            if let r = res { freeaddrinfo(r) }          // jaga-jaga: ada hasil tapi gagal
            return nil
        }
        defer { freeaddrinfo(first) }
        var found: in_addr?
        var cur: UnsafeMutablePointer<addrinfo>? = first
        while let c = cur {
            if let sa = c.pointee.ai_addr, c.pointee.ai_family == AF_INET {
                sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    found = sin.pointee.sin_addr
                }
                break
            }
            cur = c.pointee.ai_next
        }
        return found
    }
}
