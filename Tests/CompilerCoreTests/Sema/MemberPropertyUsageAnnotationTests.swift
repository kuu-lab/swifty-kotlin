@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct MemberPropertyUsageAnnotationTests {
    @Test(arguments: [false, true], [false, true])
    func implicitMutationsCheckPropertyAnnotations(optedIn: Bool, member: Bool) throws {
        let prefix = optedIn ? "@file:OptIn(ExperimentalProperty::class)\n@file:Suppress(\"DEPRECATION_ERROR\")\n" : ""
        let properties = """
        @ExperimentalProperty var count: Int = 0
        @Deprecated("use count", level = DeprecationLevel.ERROR) var old: Int = 0
        """
        let usage = """
        fun use() {
            count = 1; count += 1; ++count; count--
            val before = count++; val after = --count
            old = 1; old += 1; ++old; old--
            val oldBefore = old++; val oldAfter = --old
        }
        """
        let source = prefix + """
        @RequiresOptIn(level = RequiresOptIn.Level.WARNING)
        @Target(AnnotationTarget.PROPERTY)
        annotation class ExperimentalProperty
        """ + (member ? "\nopen class Api {\n\(properties)\n}\nclass Derived : Api() {\n\(usage)\n}" : "\n\(properties)\n\(usage)")
        TestStdlibCache.shared.prepare()
        try withTemporaryFiles(contents: [source]) { paths in
            let context = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: true)
            try runSema(context)
            let diagnostics = context.diagnostics.diagnostics
            let optIn = diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
            let deprecated = diagnostics.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }
            #expect(optIn.count == (optedIn ? 0 : 6), "\(diagnostics)")
            #expect(deprecated.count == (optedIn ? 0 : 6), "\(diagnostics)")
            #expect(diagnostics.count == optIn.count + deprecated.count, "\(diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func explicitReadsAndWritesCheckPropertyAnnotations(optedIn: Bool) throws {
        let prefix = optedIn ? "@file:OptIn(ExperimentalProperty::class)\n@file:Suppress(\"DEPRECATION_ERROR\")\n" : ""
        let source = prefix + """
        @RequiresOptIn(level = RequiresOptIn.Level.WARNING)
        @Target(AnnotationTarget.PROPERTY)
        annotation class ExperimentalProperty
        open class Api {
            @ExperimentalProperty var count: Int = 0
            @Deprecated("use count", level = DeprecationLevel.ERROR) var old: Int = 0
        }
        class Derived : Api()
        fun use(api: Derived, nullable: Api?) {
            println(api.count)
            api.count = 1
            api.count += 1
            println(nullable?.count)
            ++api.count
            api.count--
            val countBefore = api.count++
            val countAfter = --api.count
            println(api.old)
            api.old = 2
            api.old += 1
            ++api.old
            api.old--
            val oldBefore = api.old++
            val oldAfter = --api.old
        }
        """
        TestStdlibCache.shared.prepare()
        try withTemporaryFiles(contents: [source]) { paths in
            let context = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: true)
            try runSema(context)
            let diagnostics = context.diagnostics.diagnostics
            let optIn = diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
            #expect(optIn.count == (optedIn ? 0 : 8), "\(diagnostics)")
            #expect(optIn.allSatisfy { $0.severity == .warning })
            let deprecated = diagnostics.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }
            #expect(deprecated.count == (optedIn ? 0 : 7), "\(diagnostics)")
            #expect(deprecated.allSatisfy { $0.severity == .error && $0.message.contains("use count") })
            #expect(diagnostics.count == optIn.count + deprecated.count, "\(diagnostics)")
        }
    }
}
