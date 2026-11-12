import Foundation

/// Reads selected runtime-image classes through the JDK's jrt file system.
enum JVMJDKImageReader {
    static func read(image: URL, jimage: URL, patterns: [String]) -> [JVMJDKClasspath.ClassFile]? {
        let bin = jimage.deletingLastPathComponent()
        let java = bin.appendingPathComponent("java")
        guard FileManager.default.isExecutableFile(atPath: java.path),
              FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("javac").path),
              let root = try? JVMStdlibCatalog.resourceRoot() else { return nil }
        let source = root.appendingPathComponent("jvm/tools/ReadJDKClasses.java")
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = java
        process.arguments = ["--source", "11", source.path, patterns.joined(separator: ","), image.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return decode(data)
        } catch {
            return nil
        }
    }

    private static func decode(_ data: Data) -> [JVMJDKClasspath.ClassFile]? {
        var offset = 0
        func integer() -> Int? {
            guard data.count - offset >= 4 else { return nil }
            let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            offset += 4
            return Int(UInt32(bigEndian: value))
        }
        func bytes() -> Data? {
            guard let count = integer(), count <= data.count - offset else { return nil }
            let start = offset
            offset += count
            return data[start..<offset]
        }
        guard let count = integer(), count <= (data.count - offset) / 8 else { return nil }
        var classes: [(key: String, file: JVMJDKClasspath.ClassFile)] = []
        classes.reserveCapacity(count)
        for _ in 0..<count {
            guard let name = bytes().flatMap({ String(data: $0, encoding: .utf8) }),
                  let slash = name.firstIndex(of: "/"), let content = bytes() else { return nil }
            let path = String(name[name.index(after: slash)...])
            guard path.hasSuffix(".class") else { return nil }
            if path.hasPrefix("META-INF/") || path.hasSuffix("module-info.class") || path.hasSuffix("package-info.class") {
                continue
            }
            classes.append((name, .init(path: path, contents: content)))
        }
        guard offset == data.count, classes.contains(where: { $0.file.path == "java/lang/Object.class" }) else {
            return nil
        }
        return classes.sorted { $0.key < $1.key }.map(\.file)
    }
}
