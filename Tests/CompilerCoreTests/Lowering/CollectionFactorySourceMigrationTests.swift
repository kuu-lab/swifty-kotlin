#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-699: the `kotlin.collections` factory functions are source-backed
/// declarations with no bootstrap synthetic stub
/// (`HeaderHelpers+SyntheticCollectionFactoryStubs.swift` is deleted).
///
/// `CollectionLiteralLoweringTests` covers the same names, but it hand-builds
/// `.call(symbol: nil, ...)` KIR against a `KIRContext` without a `SemaModule`.
/// That short-circuits `isStdlibCollectionFactory` at its
/// `guard let sym … else { return true }`, so those cases exercise the
/// name-only fallback rather than the path a real Kotlin input takes. The
/// tests below drive the compiler from source instead, which is how the
/// `arrayListOf` / `mutableListOf` runtime-tag divergence below stayed hidden:
/// `CallLowerer` emitted `__kk_list_of` while the fallback emitted
/// `__kk_array_list_of`.
///
/// Coverage boundary: `runToKIR` is `runSema` + `BuildKIRPhase`, so it observes
/// the callee `CallLowerer` chose and nothing the `LoweringPhase` passes do
/// afterwards. That is the right stage for the factories -- `CallLowerer` claims
/// them first, so its choice is what a real build emits -- but a branch that
/// exists only in `CollectionLiteralLoweringPass` (the set/list constructors)
/// needs `runToLowering`, or the call still carries its original callee and the
/// assertion measures the stage boundary instead of the rewrite.
@Suite
struct CollectionFactorySourceMigrationTests {
    /// Every name the deleted bootstrap stub used to register, paired with the
    /// bundled file that now declares it.
    private static let factoryOwners: [String: String] = [
        "emptyList": "CollectionFactories.kt",
        "listOf": "CollectionFactories.kt",
        "mutableListOf": "CollectionFactories.kt",
        "arrayListOf": "CollectionFactories.kt",
        "listOfNotNull": "CollectionFactories.kt",
        "emptySet": "CollectionFactories.kt",
        "setOf": "CollectionFactories.kt",
        "setOfNotNull": "CollectionFactories.kt",
        "mutableSetOf": "CollectionFactories.kt",
        "emptyMap": "CollectionFactories.kt",
        "mapOf": "CollectionFactories.kt",
        "mutableMapOf": "CollectionFactories.kt",
        "hashSetOf": "hash.kt",
        "hashMapOf": "hash.kt",
        "linkedSetOf": "linked.kt",
        "linkedMapOf": "linked.kt",
    ]

    private static let factorySource = """
    fun main() {
        val a = emptyList<Int>()
        val b = listOf(1, 2)
        val c = mutableListOf(1, 2)
        val d = arrayListOf(1, 2)
        val e = listOfNotNull(1, null)
        val f = emptySet<Int>()
        val g = setOf(1, 2)
        val h = setOfNotNull(1, null)
        val i = mutableSetOf(1, 2)
        val j = hashSetOf(1, 2)
        val k = linkedSetOf(1, 2)
        val l = emptyMap<String, Int>()
        val m = mapOf("a" to 1)
        val n = mutableMapOf("a" to 1)
        val o = hashMapOf("a" to 1)
        val p = linkedMapOf("a" to 1)
    }
    """

    /// The `kotlin.collections` package FQName prefix, interned in `ctx`.
    private static func collectionsPackage(_ ctx: CompilationContext) -> [InternedString] {
        ["kotlin", "collections"].map(ctx.interner.intern)
    }

    // MARK: - declaration surface

    /// No factory name may keep a synthetic overload alongside the bundled
    /// stdlib: overload resolution could otherwise pick the stub, whose return
    /// type was `Any`, over the Kotlin declaration.
    @Test
    func factoryNamesHaveNoSyntheticOverload() throws {
        try withTemporaryFile(contents: Self.factorySource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryDeclarations",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let packageFQName = Self.collectionsPackage(ctx)
            for name in Self.factoryOwners.keys.sorted() {
                let overloads = sema.symbols.lookupAll(fqName: packageFQName + [ctx.interner.intern(name)])
                #expect(!overloads.isEmpty, "\(name) must be declared by the bundled stdlib")

                let synthetic = overloads.filter { sema.symbols.symbol($0)?.flags.contains(.synthetic) == true }
                #expect(
                    synthetic.isEmpty,
                    "\(name) must have no synthetic overload alongside the bundled stdlib"
                )
            }
        }
    }

    /// Each factory resolves into the bundled file that declares it, so the
    /// declaration the call site binds to really is Kotlin source.
    @Test
    func factoryCallsResolveIntoTheirBundledSourceFile() throws {
        try withTemporaryFile(contents: Self.factorySource) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryOwners",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let packageFQName = Self.collectionsPackage(ctx)
            for (name, expectedFile) in Self.factoryOwners.sorted(by: { $0.key < $1.key }) {
                let overloads = sema.symbols.lookupAll(fqName: packageFQName + [ctx.interner.intern(name)])
                let files: Set<String> = Set(overloads.compactMap { symbolID in
                    guard let fileID = sema.symbols.sourceFileID(for: symbolID) else { return nil }
                    return ctx.sourceManager.path(of: fileID)
                })
                #expect(
                    files.contains("__bundled_kotlin/collections/\(expectedFile)"),
                    "\(name) must be declared by \(expectedFile); resolved files: \(files.sorted())"
                )
            }
        }
    }

    /// Without the bundled stdlib nothing declares the factories any more, so
    /// no production input can reach the lowering path through a stub.
    @Test
    func noStdlibHasNoCollectionFactoryEntryPoint() throws {
        let source = """
        fun main() {
            val a = arrayListOf(1, 2)
            val b = listOf(1, 2)
            val c = mutableSetOf(1)
            val d = hashMapOf("a" to 1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryNoStdlib",
                emit: .kirDump,
                includeStdlib: false
            )
            try runToKIR(ctx)

            let unresolved = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0023" }
            for name in ["arrayListOf", "listOf", "mutableSetOf", "hashMapOf"] {
                #expect(
                    unresolved.contains { $0.message.contains("'\(name)'") },
                    "\(name) must be unresolved without stdlib; diagnostics: \(ctx.diagnostics.diagnostics)"
                )
            }

            let sema = try #require(ctx.sema)
            #expect(
                sema.symbols.lookup(fqName: Self.collectionsPackage(ctx) + [ctx.interner.intern("arrayListOf")]) == nil
            )
        }
    }

    // MARK: - production runtime routing

    /// `arrayListOf` / `mutableListOf` declare a mutable result, so their box
    /// must carry the `ArrayList` runtime tag. `__kk_list_of` tags the
    /// read-only `List`, which makes `is MutableList` / `is ArrayList` answer
    /// false on the result (verified against kotlinc in
    /// `Scripts/diff_cases/ksp699_collection_factories.kt`).
    @Test
    func mutableListFactoriesUseTheArrayListTaggedBridge() throws {
        let source = """
        fun main() {
            val emptyArrayList = arrayListOf<Int>()
            val filledArrayList = arrayListOf(1, 2)
            val emptyMutable = mutableListOf<Int>()
            val filledMutable = mutableListOf(1, 2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryMutableListTag",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.filter { $0 == "__kk_array_list_of" }.count == 4,
                "all four mutable list factory calls must use __kk_array_list_of; callees: \(callees)"
            )
            #expect(
                !callees.contains("__kk_list_of"),
                "no mutable list factory may fall back to the read-only List tag; callees: \(callees)"
            )
        }
    }

    /// The read-only counterparts must keep the `List` tag, so the fix above
    /// does not hand them a mutable nominal identity.
    @Test
    func readOnlyListFactoriesKeepTheReadOnlyTag() throws {
        let source = """
        fun main() {
            val a = listOf(1, 2)
            val b = emptyList<Int>()
            val c = listOf<Int>()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryReadOnlyListTag",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                !callees.contains("__kk_array_list_of"),
                "read-only list factories must not take the ArrayList tag; callees: \(callees)"
            )
            #expect(
                callees.contains("__kk_emptyList") || callees.contains("__kk_list_of"),
                "read-only list factories must still reach a List-tagged bridge; callees: \(callees)"
            )
        }
    }

    /// BUG-254: `mutableSetOf` / `linkedSetOf` declare a mutable result backed by
    /// LinkedHashSet, so they need the LinkedHashSet-tagged bridge. `__kk_set_of`
    /// is shared with the read-only `setOf` and tags its box as `Set`, which made
    /// `is MutableSet<*>` / `is LinkedHashSet<*>` answer false on the result
    /// (verified against kotlinc in
    /// `Scripts/diff_cases/ksp699_collection_factories.kt`).
    @Test
    func mutableSetFactoriesUseTheLinkedHashSetTaggedBridge() throws {
        let source = """
        fun main() {
            val emptyMutable = mutableSetOf<Int>()
            val filledMutable = mutableSetOf(1, 2)
            val emptyLinked = linkedSetOf<Int>()
            val filledLinked = linkedSetOf(1, 2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryMutableSetTag",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.filter { $0 == "__kk_linked_hash_set_of" }.count == 4,
                "all four mutable set factory calls must use __kk_linked_hash_set_of; callees: \(callees)"
            )
            #expect(
                !callees.contains("__kk_set_of"),
                "no mutable set factory may fall back to the read-only Set tag; callees: \(callees)"
            )
        }
    }

    /// The read-only set factories must keep the `Set` tag, so the fix above does
    /// not hand them a mutable nominal identity. kotlinc answers `true` to
    /// `setOf(1) is MutableSet<*>` only because read-only collections map onto
    /// `java.util` types on the JVM; that leak must not be reproduced here.
    @Test
    func readOnlySetFactoriesKeepTheReadOnlyTag() throws {
        let source = """
        fun main() {
            val a = setOf(1, 2)
            val b = emptySet<Int>()
            val c = setOf<Int>()
            val d = setOfNotNull(1, null)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryReadOnlySetTag",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                !callees.contains("__kk_linked_hash_set_of"),
                "read-only set factories must not take the LinkedHashSet tag; callees: \(callees)"
            )
            #expect(
                callees.contains("__kk_emptySet") || callees.contains("__kk_set_of")
                    || callees.contains("__kk_set_of_not_null"),
                "read-only set factories must still reach a Set-tagged bridge; callees: \(callees)"
            )
        }
    }

    /// `hashSetOf` keeps its own nominal tag rather than joining the LinkedHashSet
    /// bridge: `CollectionAliases.kt` declares HashSet and LinkedHashSet as
    /// independent `MutableSet` implementations.
    @Test
    func hashSetFactoryKeepsItsOwnTaggedBridge() throws {
        let source = """
        fun main() {
            val empty = hashSetOf<Int>()
            val filled = hashSetOf(1, 2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryHashSetTag",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.filter { $0 == "__kk_hash_set_of" }.count == 2,
                "both hashSetOf calls must use __kk_hash_set_of; callees: \(callees)"
            )
            #expect(
                !callees.contains("__kk_linked_hash_set_of"),
                "hashSetOf must not take the LinkedHashSet tag; callees: \(callees)"
            )
        }
    }

    /// BUG-254 also covered the LinkedHashSet constructors. Unlike the factories
    /// above, they have a single rewriter: `CallLowerer` has no constructor case,
    /// so the branch lives only in `CollectionLiteralLoweringPass`. That pass runs
    /// in `LoweringPhase`, which `runToKIR` stops short of -- hence `runToLowering`
    /// here. With `runToKIR` these calls still carry their `LinkedHashSet`
    /// constructor callee and the assertions below would describe the stage
    /// boundary rather than the rewrite.
    @Test
    func linkedHashSetConstructorsUseTheLinkedHashSetTaggedBridge() throws {
        let source = """
        fun main() {
            val empty = LinkedHashSet<Int>()
            val sized = LinkedHashSet<Int>(8)
            val copied = LinkedHashSet(listOf(1, 2))
            val hashEmpty = HashSet<Int>()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactoryLinkedHashSetConstructorTag",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.filter { $0 == "__kk_linked_hash_set_of" }.count == 2,
                """
                the 0-arg and capacity LinkedHashSet constructors must use \
                __kk_linked_hash_set_of; callees: \(callees)
                """
            )
            #expect(
                callees.contains("__kk_iterable_toMutableSet"),
                """
                the copy constructor must use __kk_iterable_toMutableSet, which is \
                retagged to LinkedHashSet; callees: \(callees)
                """
            )
            #expect(
                callees.filter { $0 == "__kk_hash_set_of" }.count == 1,
                "HashSet() must keep its own tag; callees: \(callees)"
            )
            #expect(
                !callees.contains("__kk_set_of"),
                "no set constructor may fall back to the read-only Set tag; callees: \(callees)"
            )
        }
    }

    /// The bootstrap stub set an `externalLinkName` on each factory symbol, so
    /// a leftover one would mean a stub is still being registered. The vararg
    /// overloads must also survive, since that is the shape the factory call
    /// sites bind to.
    @Test
    func factoryOverloadsKeepNoBootstrapLinkName() throws {
        let source = """
        fun main() {
            val a = arrayListOf(1, 2)
            val b = mutableListOf(1, 2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CollectionFactorySymbols",
                emit: .kirDump
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let packageFQName = Self.collectionsPackage(ctx)
            for name in ["arrayListOf", "mutableListOf"] {
                let overloads = sema.symbols.lookupAll(fqName: packageFQName + [ctx.interner.intern(name)])
                let varargOverloads = overloads.filter { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.valueParameterIsVararg.contains(true) == true
                }
                #expect(
                    !varargOverloads.isEmpty,
                    "\(name) must keep a vararg overload for the factory call sites"
                )
                for symbolID in overloads {
                    #expect(
                        sema.symbols.externalLinkName(for: symbolID) == nil,
                        "\(name) must not carry a bootstrap external link name"
                    )
                }
            }
        }
    }
}
#endif
