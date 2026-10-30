#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// KUU-3839 / KT-78073: a `fun interface` SAM constructor used directly as a
/// property delegate (`by ReadOnlyProperty { ... }`) binds its type arguments
/// from the delegate convention — the getValue `thisRef` argument supplies
/// in-position parameters and the lambda's return type supplies the rest.
@Suite
struct FunInterfaceDelegateInferenceTests {

    @Test(arguments: [false, true])
    func testSamConstructorDelegateInfersInterfaceArguments(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let source = """
        package kuu3839

        import kotlin.reflect.KProperty

        fun interface ReadOnlyProperty<in T, out V> {
            operator fun getValue(thisRef: T, property: KProperty<*>): V
        }

        val topLevel by ReadOnlyProperty { _, property -> property }

        fun box(): String {
            val property1 by ReadOnlyProperty { _, property -> property }
            return property1.name
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            let diagnostics = diagnosticsForPath(paths[0], in: ctx)
            #expect(
                diagnostics.filter { $0.severity == .error }.isEmpty,
                "SAM-converted delegate must resolve getValue and the KProperty member: \(diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
            )
        }
    }

    @Test(arguments: [false, true])
    func testSamConstructorDelegateBindsMemberThisRef(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let source = """
        package kuu3839member

        import kotlin.reflect.KProperty

        fun interface ReadOnlyProperty<in T, out V> {
            operator fun getValue(thisRef: T, property: KProperty<*>): V
        }

        class Holder {
            fun marker(): String = "member"
            val member by ReadOnlyProperty { thisRef, property -> thisRef.marker() }
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            let diagnostics = diagnosticsForPath(paths[0], in: ctx)
            #expect(
                diagnostics.filter { $0.severity == .error }.isEmpty,
                "Member delegates bind the getValue thisRef type parameter to the class: \(diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
            )
        }
    }
}
#endif
