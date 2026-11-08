#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-3944: an expression-bodied member function inferred ahead of source
/// order must resolve its inferred *member property* dependencies on demand.
/// Otherwise a caller in an earlier-compiled file sees the header `Any?`
/// placeholder, and an extension call on the result — `joinToString` here —
/// stays unresolved (KSWIFTK-SEMA-0024).
@Suite
struct CrossFileInferredMemberDependencyTests {
    @Test
    func inferredMemberReturnDependingOnInferredMemberPropertyResolvesInEitherFileOrder() throws {
        let use = """
        package sample
        fun joined(box: Box<Int>): String = box.items(1).joinToString(",")
        """
        let declarations = """
        package sample
        class Box<T> {
            private val data = linkedMapOf<T, MutableList<Int>>()
            fun items(key: T) = data[key] ?: emptyList()
        }
        """

        for sources in [[use, declarations], [declarations, use]] {
            let (sema, interner) = try SemaFixture(
                surface: "inferred member return reading an inferred member property"
            ).make(sources: sources)

            let items = try #require(sema.symbols.lookup(
                fqName: ["sample", "Box", "items"].map(interner.intern)
            ))
            // The inferred return must not stay at the header `Any?`
            // placeholder — `joinToString` resolved only because it is a
            // concrete List type.
            let returnType = try #require(sema.symbols.functionSignature(for: items)?.returnType)
            #expect(returnType != sema.types.nullableAnyType)
            #expect(returnType != sema.types.errorType)
            guard case let .classType(returnClass) = sema.types.kind(of: returnType) else {
                Issue.record("Expected a nominal List return type, got kind \(sema.types.kind(of: returnType))")
                return
            }
            #expect(returnClass.nullability == .nonNull)
            let returnSymbolName = sema.symbols.symbol(returnClass.classSymbol)?.name
            #expect(returnSymbolName == interner.intern("List") || returnSymbolName == interner.intern("MutableList"))
        }
    }

    @Test
    func inferredMemberReturnDependingOnConstructorParameterBackedPropertyResolvesInEitherFileOrder() throws {
        let use = """
        package sample
        fun readLabel(tag: Tag): Int = tag.read()
        """
        let declarations = """
        package sample
        class Tag(seed: Int) {
            private val label = seed + 1
            fun read() = label
        }
        """

        for sources in [[use, declarations], [declarations, use]] {
            let (sema, interner) = try SemaFixture(
                surface: "inferred member return reading a ctor-parameter property"
            ).make(sources: sources)

            let read = try #require(sema.symbols.lookup(
                fqName: ["sample", "Tag", "read"].map(interner.intern)
            ))
            #expect(sema.symbols.functionSignature(for: read)?.returnType == sema.types.intType)
        }
    }

    @Test
    func inferredMemberReturnDependingOnExplicitThisPropertyResolvesInEitherFileOrder() throws {
        let use = """
        package sample
        fun joined(box: Box<Int>): String = box.items(1).joinToString(",")
        """
        let declarations = """
        package sample
        class Box<T> {
            private val data = linkedMapOf<T, MutableList<Int>>()
            fun items(key: T) = this.data[key] ?: emptyList()
        }
        """

        for sources in [[use, declarations], [declarations, use]] {
            let (sema, interner) = try SemaFixture(
                surface: "inferred member return reading an inferred property via this"
            ).make(sources: sources)

            let items = try #require(sema.symbols.lookup(
                fqName: ["sample", "Box", "items"].map(interner.intern)
            ))
            let returnType = try #require(sema.symbols.functionSignature(for: items)?.returnType)
            #expect(returnType != sema.types.nullableAnyType)
            #expect(returnType != sema.types.errorType)
            guard case let .classType(returnClass) = sema.types.kind(of: returnType) else {
                Issue.record("Expected a nominal List return type, got kind \(sema.types.kind(of: returnType))")
                return
            }
            let returnSymbolName = sema.symbols.symbol(returnClass.classSymbol)?.name
            #expect(returnSymbolName == interner.intern("List") || returnSymbolName == interner.intern("MutableList"))
        }
    }

    @Test
    func inferredObjectMemberReturnDependingOnInferredMemberPropertyResolvesInEitherFileOrder() throws {
        let use = """
        package sample
        fun sizeOf(text: String): Int = Registry.sizeOf(text)
        """
        let declarations = """
        package sample
        object Registry {
            private val table = linkedMapOf<String, Int>()
            fun sizeOf(key: String) = table[key] ?: 0
        }
        """

        for sources in [[use, declarations], [declarations, use]] {
            let (sema, interner) = try SemaFixture(
                surface: "inferred object member return reading an inferred member property"
            ).make(sources: sources)

            let sizeOf = try #require(sema.symbols.lookup(
                fqName: ["sample", "Registry", "sizeOf"].map(interner.intern)
            ))
            #expect(sema.symbols.functionSignature(for: sizeOf)?.returnType == sema.types.intType)
        }
    }

    /// KUU-4479: operator desugars (`o[i]`, `o + x`, `-o`, `o[i] += v`) must
    /// infer a forward-declared operator member's expression-body return type
    /// on demand instead of reading the header's `Any` placeholder, which used
    /// to surface as KSWIFTK-SEMA-0469 against the caller's declared return.
    @Test
    func forwardDeclaredOperatorMembersInferReturnTypesForOperatorSyntax() throws {
        let uses = """
        package sample
        fun selGet(o: OpBox, i: Int): Int = o[i]
        fun selPlus(o: OpBox, x: Int): Int = o + x
        fun selMinus(o: OpBox, x: Int): Int = o - x
        fun selNeg(o: OpBox): Int = -o
        fun selSet(o: OpBox, i: Int, v: Int) { o[i] = v }
        fun selInvoke(o: OpBox): Int = o()
        fun selCompare(o: OpBox, x: OpBox): Boolean = o < x
        fun selContains(o: OpBox, i: Int): Boolean = i in o
        fun selCompound(o: OpBox, i: Int) { o[i] += 5 }
        """
        let declarations = """
        package sample
        class OpBox(val x: Int) {
            operator fun get(i: Int) = i
            operator fun set(i: Int, v: Int) {}
            operator fun plus(v: Int) = v
            operator fun minus(v: Int) = v
            operator fun unaryMinus() = -x
            operator fun compareTo(o: OpBox) = x - o.x
            operator fun contains(i: Int) = i == x
            operator fun invoke() = 7
        }
        """

        for sources in [[uses + "\n" + declarations], [uses, declarations], [declarations, uses]] {
            _ = try SemaFixture(
                surface: "forward-declared operator member inferred returns"
            ).make(sources: sources)
        }
    }
}
#endif
