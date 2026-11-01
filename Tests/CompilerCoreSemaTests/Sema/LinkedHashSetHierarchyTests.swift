@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct LinkedHashSetHierarchyTests {
    @Test(arguments: [false, true])
    func linkedHashSetHasGenericHashSetSupertype(useArtifact: Bool) throws {
        let ctx = try context("""
        fun main() {
            val lhs = LinkedHashSet<Int>()
            lhs.add(1)
            println(lhs is HashSet<Int>)
            val viaSub: HashSet<Int> = lhs
            println(viaSub.size)
        }
        fun nullableElements(lhs: LinkedHashSet<String?>): HashSet<String?> = lhs
        """, useArtifact: useArtifact)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let linked = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "LinkedHashSet"].map(ctx.interner.intern)))
        let hash = try #require(sema.symbols.lookup(fqName: ["kotlin", "collections", "HashSet"].map(ctx.interner.intern)))
        #expect(sema.symbols.directSupertypes(for: linked).contains(hash))
        let element = try #require(sema.types.nominalTypeParameterSymbols(for: linked).first)
        let elementType = sema.types.make(.typeParam(TypeParamType(symbol: element, nullability: .nonNull)))
        #expect(sema.types.nominalSupertypeTypeArgs(for: linked, supertype: hash) == [.invariant(elementType)])
    }

    @Test(arguments: [false, true])
    func reverseAssignmentAndDifferentElementTypesRemainInvalid(useArtifact: Bool) throws {
        let ctx = try context("""
        fun reverse(value: HashSet<Int>): LinkedHashSet<Int> = value
        fun different(value: LinkedHashSet<Int>): HashSet<String> = value
        fun widened(value: LinkedHashSet<String>): HashSet<Any> = value
        """, useArtifact: useArtifact)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 3, "\(ctx.diagnostics.diagnostics)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0469" })
    }

    private func context(_ source: String, useArtifact: Bool) throws -> CompilationContext {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource(
            source,
            emit: useArtifact ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useArtifact
        )
        try runSema(ctx)
        return ctx
    }
}
