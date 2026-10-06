#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct DurationFactoryImportTests {
    private static let units = [
        "nanoseconds", "microseconds", "milliseconds", "seconds", "minutes", "hours", "days",
    ]
    private static let factories = units.flatMap { unit in
        ["1", "2L", "1.5"].map { "println(\($0).\(unit))" }
    }.joined(separator: "\n")

    @Test(arguments: ["", "import kotlin.time.*", "import kotlin.time.Duration"])
    func factoriesRequireCompanionImports(imports: String) throws {
        try withTemporaryFile(contents: "\(imports)\nfun main() {\n\(Self.factories)\n}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 21, "Got: \(errors)")
            for unit in Self.units {
                #expect(errors.contains { $0.message.contains(unit) })
            }
        }
    }

    @Test
    func explicitImportsResolveAllNumericFactories() throws {
        let imports = Self.units.map { "import kotlin.time.Duration.Companion.\($0)" }
            .joined(separator: "\n")
        let (sema, interner) = try SemaFixture(surface: "Duration factories").make(
            source: "\(imports)\nfun main() {\n\(Self.factories)\n}"
        )
        let package = ["kotlin", "time"].map { interner.intern($0) }
        let companion = package + [interner.intern("Duration"), interner.intern("Companion")]
        for unit in Self.units {
            let name = interner.intern(unit)
            #expect(sema.symbols.lookupAll(fqName: package + [name]).isEmpty)
            let properties = sema.symbols.lookupAll(fqName: companion + [name]).filter {
                sema.symbols.symbol($0)?.kind == .property
            }
            #expect(properties.count == 3)
            let receivers = properties.compactMap { sema.symbols.extensionPropertyReceiverType(for: $0) }
            for receiver in [sema.types.intType, sema.types.longType, sema.types.doubleType] {
                #expect(receivers.contains(receiver))
            }
        }
    }

    @Test
    func aliasesAndCompanionReceiverScopesResolve() throws {
        _ = try SemaFixture(surface: "Duration companion scope").make(source: """
        import kotlin.time.Duration
        import kotlin.time.Duration.Companion.seconds as sec

        fun main() {
            println(1.sec)
            println(2L.sec)
            println(1.5.sec)
            Duration.run { println(1.seconds); println(2L.minutes); println(1.5.hours) }
            with(Duration) { println(1.days); println(2L.microseconds); println(1.5.nanoseconds) }
        }
        """)
    }

    @Test
    func importsDoNotLeakToOtherNamesOrFiles() throws {
        let sources = [
            "import kotlin.time.Duration.Companion.seconds\nfun imported() = 1.seconds",
            "fun unimported() = 1.seconds",
            "import kotlin.time.Duration.Companion.seconds as sec\nfun original() = 1.seconds",
            "import kotlin.time.Duration.Companion.seconds\nfun otherUnit() = 1.minutes",
            "package kotlin.time\nfun samePackage() = 1.seconds",
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(diagnosticsForPath(paths[0], in: ctx).allSatisfy { $0.severity != .error })
            for path in paths.dropFirst() {
                #expect(diagnosticsForPath(path, in: ctx).contains { $0.severity == .error })
            }
        }
    }
}
#endif
