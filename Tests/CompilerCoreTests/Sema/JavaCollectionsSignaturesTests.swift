@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct JavaCollectionsSignaturesTests {
    private static let collectionDeclarations = """
    package kotlin.collections
    interface MutableMap<K, V>
    interface MutableSet<E>
    """

    /// A user-defined Kotlin object with the Java FQN is still a Kotlin API.
    @Test
    func userDeclarationRetainsKotlinMapArguments() throws {
        let source = """
        package java.util
        object Collections {
            fun <E> newSetFromMap(map: MutableMap<E, out Boolean?>?): MutableSet<E> = throw null!!
        }
        """
        try withTemporaryFiles(contents: [Self.collectionDeclarations, source]) { inputs in
            let context = makeCompilationContext(inputs: inputs, includeStdlib: false, allowDefaultStdlibLibrary: false)
            try runFrontend(context)
            try DataFlowSemaPhase().run(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let function = try #require(sema.symbols.lookup(fqName: ["java", "util", "Collections", "newSetFromMap"].map(context.interner.intern)))
            let signature = try #require(sema.symbols.functionSignature(for: function))
            guard case let .classType(map) = sema.types.kind(of: signature.parameterTypes[0]),
                  case let .invariant(element) = map.args[0],
                  case let .out(value) = map.args[1] else {
                Issue.record("Expected the declared Kotlin MutableMap parameter")
                return
            }
            #expect(sema.types.nullability(of: element) == .nonNull)
            #expect(sema.types.nullability(of: value) == .nullable)
        }
    }

    /// Check the JVM acceptance boundary using a minimal bundled facade so
    /// this Sema regression does not rebuild the entire stdlib artifact.
    @Test
    func mapTypeParameterBoundsRetainTheBooleanValueConstraint() throws {
        let facade = """
        package java.util
        object Collections {
            fun <E> newSetFromMap(map: MutableMap<E, out Boolean?>?): MutableSet<E> = throw null!!
        }
        """
        let consumer = """
        import java.util.Collections
        interface Marker
        fun <M : MutableMap<String, Boolean>> bounded(map: M): MutableSet<String> = Collections.newSetFromMap(map)
        fun <M : MutableMap<String, Boolean?>> nullableBounded(map: M): MutableSet<String> = Collections.newSetFromMap(map)
        fun <M> intersection(map: M): MutableSet<String> where M : Marker, M : MutableMap<String, Boolean> = Collections.newSetFromMap(map)
        fun inferOut(map: MutableMap<out String, Boolean>) = Collections.newSetFromMap(map)
        fun inferIn(map: MutableMap<in String, Boolean>) = Collections.newSetFromMap(map)
        fun inferStar(map: MutableMap<*, Boolean>) = Collections.newSetFromMap(map)
        fun <B : Boolean, M : MutableMap<String, B>> rejected(map: M): MutableSet<String> = Collections.newSetFromMap(map)
        fun rejectOut(map: MutableMap<out String, Boolean>): MutableSet<String> = Collections.newSetFromMap(map)
        fun rejectIn(map: MutableMap<in String, Boolean>): MutableSet<String> = Collections.newSetFromMap(map)
        fun rejectStar(map: MutableMap<*, Boolean>): MutableSet<Any?> = Collections.newSetFromMap(map)
        fun rejectExplicit(map: MutableMap<out String, Boolean>) = Collections.newSetFromMap<String>(map)
        fun nullableArgument(map: MutableMap<String, Boolean>): MutableSet<String?> = Collections.newSetFromMap<String?>(map)
        fun nullableOutput(map: MutableMap<String?, Boolean>): MutableSet<String> = Collections.newSetFromMap<String?>(map)
        """
        try withTemporaryFiles(contents: [Self.collectionDeclarations, facade, consumer]) { inputs in
            let context = makeCompilationContext(inputs: inputs, includeStdlib: false, allowDefaultStdlibLibrary: false)
            _ = context.sourceManager.addFile(path: inputs[1], contents: Data(facade.utf8), origin: .bundledStdlib)
            do { try runSema(context) } catch {}
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0002" },
                    "The map with a Boolean-bounded value parameter must fail overload resolution: \(errors)")
            let rejectedLines: Set<Int> = [9, 10, 11, 12, 13]
            let lines = Set(errors.compactMap { diagnostic -> Int? in
                guard let location = diagnostic.primaryRange?.start,
                      context.sourceManager.path(of: location.file) == inputs[2] else { return nil }
                return context.sourceManager.lineColumn(of: location).line
            })
            #expect(rejectedLines.isSubset(of: lines), "Every rejected capture/value case must diagnose: \(errors)")
            #expect(errors.allSatisfy { diagnostic in
                guard let location = diagnostic.primaryRange?.start else { return false }
                return context.sourceManager.path(of: location.file) == inputs[2]
                    && rejectedLines.contains(context.sourceManager.lineColumn(of: location).line)
            }, "Only the capture and value-type-parameter controls must be rejected: \(errors)")
            #expect(context.diagnostics.diagnostics.contains {
                $0.severity == .warning && $0.code == "KSWIFTK-SEMA-0431"
            })
        }
    }

}
