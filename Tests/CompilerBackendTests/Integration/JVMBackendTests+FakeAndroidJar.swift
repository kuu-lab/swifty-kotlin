#if canImport(Testing)
import Foundation
import Testing

extension JVMBackendTests {
    /// A stand-in `android.jar` for fake SDKs. The JVM stdlib declares
    /// `BigDecimal` operators against the platform's `java.math`, which a
    /// real android.jar provides, so the stub carries exactly that surface.
    func writeFakeAndroidJar(to jar: URL, root: URL) throws {
        let sources = root.appendingPathComponent("fake-android-src/java/math", isDirectory: true)
        let classes = root.appendingPathComponent("fake-android-classes", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: classes, withIntermediateDirectories: true)
        try """
        package java.math;
        public class BigDecimal {
            public static final BigDecimal ONE = null;
            public BigDecimal add(BigDecimal other) { return null; }
            public BigDecimal subtract(BigDecimal other) { return null; }
            public BigDecimal multiply(BigDecimal other) { return null; }
            public BigDecimal divide(BigDecimal other, RoundingMode mode) { return null; }
            public BigDecimal remainder(BigDecimal other) { return null; }
            public BigDecimal negate() { return null; }
        }
        """.write(to: sources.appendingPathComponent("BigDecimal.java"), atomically: true, encoding: .utf8)
        try "package java.math; public final class RoundingMode { public static final RoundingMode HALF_EVEN = null; }"
            .write(to: sources.appendingPathComponent("RoundingMode.java"), atomically: true, encoding: .utf8)
        let base = sources.deletingLastPathComponent().deletingLastPathComponent()
        let compiled = try jvmTool("javac", [
            "--patch-module", "java.base=\(base.path)", "-d", classes.path,
            sources.appendingPathComponent("BigDecimal.java").path, sources.appendingPathComponent("RoundingMode.java").path,
        ], root: root)
        try #require(compiled.exitCode == 0, "\(compiled.stderr)")
        _ = try jvmTool("jar", ["cf", jar.path, "-C", classes.path, "."], root: root)
    }
}
#endif
