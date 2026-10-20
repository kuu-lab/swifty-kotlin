import Foundation

/// A deterministic, uncompressed ZIP archive. JVM output does not require a
/// JDK, an external jar tool, or a Native linker on the compilation host.
enum JVMJarArchive {
    static func emit(className: String, classFile: Data, hasMain: Bool = true, module: (String, Data)? = nil, classes: [(String, Data)] = []) throws -> Data {
        let mainClass = className.replacingOccurrences(of: "/", with: ".")
        let mainLine = Array("Main-Class: \(mainClass)".utf8)
        var manifest = Data("Manifest-Version: 1.0\r\n".utf8)
        // Manifest lines may not exceed 72 bytes including CRLF.
        var offset = 0
        while hasMain && offset < mainLine.count {
            if offset > 0 { manifest.append(0x20) }
            let end = min(offset + (offset == 0 ? 70 : 69), mainLine.count)
            manifest.append(contentsOf: mainLine[offset..<end])
            manifest.append(contentsOf: [13, 10])
            offset = end
        }
        manifest.append(contentsOf: [13, 10])
        var entries: [(String, Data)] = [
            ("META-INF/MANIFEST.MF", manifest),
            (className + ".class", classFile),
        ]
        entries += classes
        if let module { entries.append(module) }
        guard entries.count <= 65_535 else { throw JVMEmissionError.limit("JVM JAR entry limit exceeded.") }
        var archive = Data()
        var directory = Data()
        for (name, contents) in entries {
            let filename = Data(name.utf8)
            guard filename.count <= 65_535, contents.count <= Int(UInt32.max),
                  archive.count <= Int(UInt32.max) else {
                throw JVMEmissionError.limit("JVM JAR exceeds the supported ZIP size limits.")
            }
            let crc = crc32(contents)
            let entryOffset = UInt32(archive.count)
            archive.le4(0x04034B50)
            archive.le2(20); archive.le2(0x0800); archive.le2(0) // version, UTF-8, stored
            archive.le2(0); archive.le2(0x0021) // 1980-01-01, deterministic timestamp
            archive.le4(crc); archive.le4(UInt32(contents.count)); archive.le4(UInt32(contents.count))
            archive.le2(UInt16(filename.count)); archive.le2(0)
            archive.append(filename); archive.append(contents)

            directory.le4(0x02014B50)
            directory.le2(20); directory.le2(20); directory.le2(0x0800); directory.le2(0)
            directory.le2(0); directory.le2(0x0021)
            directory.le4(crc); directory.le4(UInt32(contents.count)); directory.le4(UInt32(contents.count))
            directory.le2(UInt16(filename.count)); directory.le2(0); directory.le2(0)
            directory.le2(0); directory.le2(0); directory.le4(0); directory.le4(entryOffset)
            directory.append(filename)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.le4(0x06054B50)
        archive.le2(0); archive.le2(0); archive.le2(UInt16(entries.count)); archive.le2(UInt16(entries.count))
        archive.le4(UInt32(directory.count)); archive.le4(directoryOffset); archive.le2(0)
        return archive
    }

    private static func crc32(_ contents: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in contents {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xEDB88320)
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func le2(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func le4(_ value: UInt32) {
        le2(UInt16(truncatingIfNeeded: value))
        le2(UInt16(truncatingIfNeeded: value >> 16))
    }
}
