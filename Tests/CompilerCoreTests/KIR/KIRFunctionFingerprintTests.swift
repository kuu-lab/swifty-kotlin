#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KUU-3019: the fingerprint must be a function of a function's own content,
/// never of how many symbols, types or expressions were created before it.
@Suite
struct KIRFunctionFingerprintTests {
    /// Raw `SymbolID` of each function by simple name from the last
    /// `fingerprints` call, to prove a test really shifts the numbering.
    private final class RawIDs: @unchecked Sendable {
        var byName: [String: Int32] = [:]
    }

    private let rawIDs = RawIDs()

    private func fingerprints(_ source: String) throws -> [String: KIRFunctionFingerprint] {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        rawIDs.byName = [:]
        for case let .function(function) in module.arena.declarations {
            rawIDs.byName[ctx.interner.resolve(function.name)] = function.symbol.rawValue
        }
        return module.functionFingerprints(interner: ctx.interner, symbols: sema.symbols, types: sema.types)
    }

    private func hash(_ prints: [String: KIRFunctionFingerprint], _ name: String) throws -> String {
        let matches = prints.values.filter { $0.key.hasSuffix("|\(name)") || $0.key.contains("|\(name)(") }
        let match = try #require(matches.first, "no fingerprint for \(name) in \(prints.keys.sorted())")
        #expect(matches.count == 1, "ambiguous \(name): \(matches.map(\.key))")
        return match.hash
    }

    private let base = """
    fun helper(x: Int): Int = x + 1
    fun a(): Int = helper(10) * 2
    fun b(s: String): String = s
    """

    @Test
    func identicalSourceGivesIdenticalFingerprints() throws {
        let first = try fingerprints(base)
        let second = try fingerprints(base)
        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test
    func insertingUnrelatedDeclarationsDoesNotChangeExistingFingerprints() throws {
        let before = try fingerprints(base)
        let rawBefore = rawIDs.byName
        // The prefix creates symbols, types (generic class, function type) and
        // expressions ahead of everything in `base`, shifting every raw id.
        let shifted = try fingerprints("""
        class Box<T>(val value: T) { fun get(): T = value }
        fun unrelated(f: (Int) -> String, n: Int): String = f(n)
        fun another(): Int = 1 + 2 + 3
        \(base)
        """)
        for name in ["helper", "a", "b"] {
            #expect(rawBefore[name] != rawIDs.byName[name], "\(name): raw SymbolID should have shifted")
            #expect(try hash(before, name) == hash(shifted, name), "\(name) must not depend on declaration order")
        }
        #expect(shifted.count > before.count)
    }

    @Test
    func genericClassMembersAreStableUnderUnrelatedInsertions() throws {
        // A class type parameter's FQ name embeds the class's raw SymbolID.
        let box = "class Box<T>(val value: T) { fun get(): T = value }\nfun use(b: Box<Int>): Int = b.get()"
        let before = try fingerprints(box)
        let after = try fingerprints("class Pair2<A, B>(val a: A, val b: B)\nfun noise(): Int = 1\n\(box)")
        for needle in [".get(", "|use"] {
            let lhs = try #require(before.values.first { $0.key.contains(needle) })
            let rhs = try #require(after.values.first { $0.key.contains(needle) })
            #expect(lhs.hash == rhs.hash, "\(needle) must not depend on declaration order")
            #expect(lhs.key == rhs.key)
        }
    }

    @Test
    func bodyEditChangesOnlyTheEditedFunction() throws {
        let before = try fingerprints(base)
        let after = try fingerprints(base.replacingOccurrences(of: "x + 1", with: "x + 2"))
        #expect(try hash(before, "helper") != hash(after, "helper"))
        #expect(try hash(before, "a") == hash(after, "a"))
        #expect(try hash(before, "b") == hash(after, "b"))
    }

    @Test
    func changingACalleeOrLiteralChangesTheCaller() throws {
        let before = try fingerprints(base)
        let literal = try fingerprints(base.replacingOccurrences(of: "helper(10)", with: "helper(11)"))
        #expect(try hash(before, "a") != hash(literal, "a"))

        let otherCallee = try fingerprints("""
        fun helper(x: Int): Int = x + 1
        fun helper2(x: Int): Int = x + 1
        fun a(): Int = helper2(10) * 2
        fun b(s: String): String = s
        """)
        #expect(try hash(before, "a") != hash(otherCallee, "a"))
    }

    @Test
    func recordsReferencesAndExcludesOwnParameters() throws {
        let prints = try fingerprints(base)
        let a = try #require(prints.values.first { $0.key.contains("|a") })
        #expect(a.references.contains { $0.contains("helper") })
        let helper = try #require(prints.values.first { $0.key.contains("|helper") })
        #expect(!helper.references.contains { $0.contains("|x") }, "parameter symbols are positional, not references")
    }

    @Test
    func overloadsWithTheSameNameGetDistinctKeys() throws {
        let prints = try fingerprints("""
        fun f(x: Int): Int = x
        fun f(x: String): String = x
        """)
        let keys = prints.values.map(\.key).filter { $0.contains("|f") }
        #expect(keys.count == 2)
        #expect(Set(keys).count == 2)
    }

    @Test
    func parameterAndReturnTypesAreIncluded() throws {
        let intVersion = try fingerprints("fun f(x: Int): Int = x")
        let longVersion = try fingerprints("fun f(x: Long): Long = x")
        #expect(try hash(intVersion, "f") != hash(longVersion, "f"))
    }
}
#endif
