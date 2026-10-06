#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct UnsignedArrayOptInTests {
    private func check(
        _ source: String,
        frontendFlags: [String] = [],
        expectedWarningLines: Set<Int> = []
    ) throws -> [Diagnostic] {
        let ctx = makeContextFromSource(source, frontendFlags: frontendFlags)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let bundledWarnings = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
                && $0.message.contains("kotlin.ExperimentalUnsignedTypes")
                && $0.primaryRange.map { ctx.sourceManager.origin(of: $0.start.file)?.isBundledStdlib == true } == true
        }
        #expect(bundledWarnings.isEmpty, "Bundled implementation must opt in: \(bundledWarnings)")
        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
                && $0.primaryRange.map { ctx.sourceManager.origin(of: $0.start.file) == .user } == true
        }
        let warningLines = Set(diagnostics.compactMap { diagnostic in
            diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line }
        })
        #expect(warningLines.isSuperset(of: expectedWarningLines), "\(diagnostics)")
        return diagnostics
    }

    @Test(arguments: ["UInt", "ULong", "UByte", "UShort"])
    func factoriesAndSizeRequireWarning(_ type: String) throws {
        let factory = type.lowercased() + "ArrayOf"
        let diagnostics = try check("""
        fun main() {
            val u = \(factory)(1u)
            println(u.size)
        }
        """, expectedWarningLines: [2, 3])
        #expect(diagnostics.count >= 2, "Expected warnings for factory and size: \(diagnostics)")
        #expect(diagnostics.allSatisfy { $0.severity == .warning })
        #expect(diagnostics.allSatisfy { $0.message.contains("kotlin.ExperimentalUnsignedTypes") })
    }

    @Test(arguments: ["UInt", "ULong", "UByte", "UShort"])
    func constructorsAndTypeAnnotationsRequireWarning(_ type: String) throws {
        let diagnostics = try check("""
        fun allocate() { val u = \(type)Array(1) }
        fun initialize() { val u = \(type)Array(1) { 1u } }
        fun use(u: \(type)Array) {}
        """, expectedWarningLines: [1, 2, 3])
        #expect(diagnostics.allSatisfy { $0.severity == .warning })
    }

    @Test
    func unsignedArrayConversionsRequireWarning() throws {
        let diagnostics = try check("""
        fun main() {
            val signed = intArrayOf(1)
            val view = signed.asUIntArray()
            val copy = signed.toUIntArray()
            println(view.toList())
        }
        """, expectedWarningLines: [3, 4, 5])
        #expect(diagnostics.allSatisfy { $0.severity == .warning })
    }

    @Test
    func extensionPropertyAnnotationsRequireOptIn() throws {
        let diagnostics = try check("""
        @RequiresOptIn(level = RequiresOptIn.Level.WARNING)
        @Target(AnnotationTarget.PROPERTY)
        annotation class ExperimentalProperty
        @ExperimentalProperty
        val String.experimentalLength: Int get() = length
        fun main() { println("x".experimentalLength) }
        """, expectedWarningLines: [6])
        #expect(diagnostics.contains { $0.message.contains("ExperimentalProperty") })
        #expect(diagnostics.allSatisfy { $0.severity == .warning })
    }

    @Test
    func unsignedVarargComparisonRequiresWarning() throws {
        let diagnostics = try check("""
        fun main() {
            val value: UInt = 1u
            println(maxOf(value, value, value, value))
            println(minOf(value, value, value, value))
        }
        """, expectedWarningLines: [3, 4])
        #expect(diagnostics.allSatisfy { $0.severity == .warning })
    }

    @Test(arguments: [
        "@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)",
        "@OptIn(kotlin.ExperimentalUnsignedTypes::class)",
        "@kotlin.ExperimentalUnsignedTypes",
    ])
    func explicitOptInSuppressesWarnings(_ annotation: String) throws {
        let diagnostics = try check("""
        \(annotation)
        fun main() {
            val u = uintArrayOf(1u)
            val v: UIntArray = UIntArray(1) { 1u }
            println(u.size + v.size)
        }
        """)
        #expect(diagnostics.isEmpty, "\(diagnostics)")
    }

    @Test
    func compilerOptInSuppressesWarnings() throws {
        let diagnostics = try check(
            "fun main() { val u = uintArrayOf(1u); println(u.size) }",
            frontendFlags: ["opt-in=kotlin.ExperimentalUnsignedTypes"]
        )
        #expect(diagnostics.isEmpty, "\(diagnostics)")
    }

    @Test
    func scalarUnsignedAndSignedArraysRemainStable() throws {
        let diagnostics = try check("""
        import kotlinx.io.bytestring.ByteString

        fun main() {
            val i: UInt = 1u
            val l: ULong = 1uL
            val b: UByte = 1u
            val s: UShort = 1u
            val maximum = maxOf(i, i, i)
            val bytes = ByteString(b, b)
            val a = intArrayOf(1)
            val c = IntArray(1)
            println(a.size + c.size)
        }
        """)
        #expect(diagnostics.isEmpty, "\(diagnostics)")
    }
}
#endif
