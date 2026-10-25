#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DataClassComponentNTests {

    // Regression test for the bug reported in PR #1281 follow-up:
    // specializeComponentReturnType was applied only to inferDestructuringDeclExpr
    // but NOT to inferForDestructuringExpr, so for-loop destructuring of generic
    // Pair/tuple types still returned the raw type-parameter instead of the
    // concrete substituted type.

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testForLoopDestructuringPairSpecializesComponentReturnType
            """
            package sample0

                    fun demo() {
                        val pairs: List<Pair<String, Int>> = listOf(Pair("a", 1), Pair("b", 2))
                        for ((k, v) in pairs) {
                            k.length + v
                        }
                    }

            """,
            // testComponentNUsesOwnerVisibilityForPrivateDataClass
            """
            package sample1

                    package test

                    private data class Secret(val value: Int)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testForLoopDestructuringPairSpecializesComponentReturnType ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(
                    !(sample0Diagnostics.contains { $0.severity == .error }),
                    "Expected for-loop pair destructuring to compile without sema errors, got: \(sample0Diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: ", "))"
                )

            }

            // === testComponentNUsesOwnerVisibilityForPrivateDataClass ===

            do {

                let sample1Path = paths[1]


                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let componentFQName = [
                    interner.intern("test"),
                    interner.intern("Secret"),
                    interner.intern("component1"),
                ]

                let componentSymbolID = try #require(sema.symbols.lookupAll(fqName: componentFQName).first)
                let componentSymbol = try #require(sema.symbols.symbol(componentSymbolID))

                #expect(componentSymbol.visibility == .private)
                #expect(
                    !(sample1Diagnostics.contains { $0.severity == .error }),
                    "Unexpected diagnostics: \(sample1Diagnostics.map(\.message))"
                )

            }

        }
    }

    @Test
    func testForLoopDestructuringConcreteMapSubtype() throws {
        let source = """
        fun main() {
            val values = linkedMapOf("a" to 1)
            for ((key, value) in values) {
                println("$key=$value")
            }
        }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Concrete LinkedHashMap destructuring should type-check: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test
    func testDataClassDestructuringReportsMissingComponents() throws {
        let source = """
        interface TestIterator<E> {
            operator fun hasNext(): Boolean
            operator fun next(): E
        }

        interface TestIterable<E> {
            operator fun iterator(): TestIterator<E>
        }

        data class C(val first: Int, val second: Int)

        fun parenthesizedForLoop(items: TestIterable<C>) {
            for ((x, _, z) in items) {}
        }

        fun bracketedForLoop(items: TestIterable<C>) {
            for ([x, _, z] in items) {}
        }

        fun destructuringDeclaration(value: C) {
            val (x, _, z) = value
        }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)

            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            let missingComponentErrors = errors.filter { $0.message.contains("component3()") }

            #expect(
                missingComponentErrors.count == 3,
                "Expected a missing component3 diagnostic for both for-loop delimiters and a local declaration, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
            #expect(
                errors.filter { $0.code == "KSWIFTK-SEMA-0087" }.count == 2,
                "Expected both for-loop forms to report KSWIFTK-SEMA-0087, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
            #expect(
                errors.filter { $0.code == "KSWIFTK-SEMA-0086" }.count == 1,
                "Expected the local destructuring declaration to report KSWIFTK-SEMA-0086, got: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    @Test
    func testForLoopDestructuringBracketSyntaxWithArrayListPairs() throws {
        let source = """
        interface ArrayListIterator<E> {
            operator fun hasNext(): Boolean
            operator fun next(): E
        }

        interface ArrayList<E> {
            operator fun iterator(): ArrayListIterator<E>
        }

        interface Pair<A, B> {
            operator fun component1(): A
            operator fun component2(): B
        }

        fun probe(alist: ArrayList<Pair<Int, Int>>) {
            var result = 0
            for ([i: Int, z: Int] in alist) {
                result += i + z
            }
        }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                includeStdlib: false
            )
            try runSema(ctx)

            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Bracket destructuring over ArrayList<Pair<Int, Int>> should type-check: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    // KUU-3254: a generated componentN() must be able to override the
    // closest superclass member with the same name and arity. A member that
    // is effectively final, or whose return type is incompatible with the
    // generated one, reports KSWIFTK-SEMA-0442 at the data class. Interface,
    // abstract and private members never conflict.
    @Test
    func testComponentNSupertypeConflictDiagnostics() throws {
        let sources: [String] = [
            // 0: final-by-default class member conflicts.
            """
            package s0
            open class Base { fun component1(): String = "x" }
            data class FinalMember(val field: String) : Base()
            """,
            // 1: explicit `final` member conflicts too.
            """
            package s1
            open class Base { final fun component1(): String = "x" }
            data class ExplicitFinal(val field: String) : Base()
            """,
            // 2: the conflict follows the inheritance chain up to the
            //    defining class.
            """
            package s2
            open class Base { fun component1(): String = "x" }
            abstract class Mid : Base()
            data class DeepConflict(val field: String) : Mid()
            """,
            // 3: a different return type still conflicts for a final member.
            """
            package s3
            open class Base { fun component1(): Int = 1 }
            data class FinalReturnMismatch(val field: String) : Base()
            """,
            // 4: an overridable member with an incompatible return type
            //    also conflicts.
            """
            package s4
            open class Base { open fun component1(): Int = 1 }
            data class OpenReturnMismatch(val field: String) : Base()
            """,
            // 5: an overridable member with a covariant return type is a
            //    legitimate override target.
            """
            package s5
            open class Base { open fun component1(): Number = 1 }
            data class CovariantReturn(val field: Int) : Base()
            """,
            """
            package s6
            open class Base { open fun component1(): Any = "x" }
            data class AnyReturn(val field: String) : Base()
            """,
            // 7: interface members — abstract or default — are implemented
            //    by the generated componentN.
            """
            package s7
            interface I { fun component1(): String }
            data class InterfaceMember(val field: String) : I
            """,
            """
            package s8
            interface I { fun component1(): String = "i" }
            data class InterfaceDefault(val field: String) : I
            """,
            // 9: abstract class abstract members are implemented too.
            """
            package s9
            abstract class Base { abstract fun component1(): String }
            data class AbstractMember(val field: String) : Base()
            """,
            // 10: private superclass members are invisible.
            """
            package s10
            open class Base { private fun component1(): String = "x" }
            data class PrivateMember(val field: String) : Base()
            """,
            // 11: members with parameters never conflict.
            """
            package s11
            open class Base { fun component1(n: Int): String = "x" }
            data class ParameterisedMember(val field: String) : Base()
            """,
            // 12: only the generated indices conflict — component2 of the
            //     supertype does not clash with a single-property class.
            """
            package s12
            open class Base { fun component2(): Int = 2 }
            data class SingleProperty(val field: String) : Base()
            """,
            // 13: a conflicting index is diagnosed while later indices are
            //     still free to generate.
            """
            package s13
            open class Base { fun component1(): String = "x" }
            data class TwoProperties(val field: String, val n: Int) : Base()
            """,
            // 14: a property named componentN is not a function member.
            """
            package s14
            open class Base { val component1: String get() = "x" }
            data class PropertyMember(val field: String) : Base()
            """,
            // 15: an open member in the direct superclass is overridable.
            """
            package s15
            open class Base { open fun component1(): String = "x" }
            data class OpenMember(val field: String) : Base()
            """,
            // 16: an interface member with an incompatible return type
            //     conflicts — the generated member cannot validly implement it.
            """
            package s16
            interface I { fun component1(): Int }
            data class InterfaceMismatch(val field: String) : I
            """,
            // 17: an abstract member with different arity is not implemented
            //     by the generated componentN — reported by the abstract
            //     member check, not the conflict check.
            """
            package s17
            interface I { fun component1(n: Int): String }
            data class InterfaceArity(val field: String) : I
            """,
            // 18: an abstract class member with an incompatible return type
            //     conflicts just like an interface member.
            """
            package s18
            abstract class Base { abstract fun component1(): Int }
            data class AbstractMismatch(val field: String) : Base()
            """,
            // 19: with two interfaces, only the incompatible member conflicts.
            """
            package s19
            interface I1 { fun component1(): String }
            interface I2 { fun component1(): Int }
            data class TwoInterfaces(val field: String) : I1, I2
            """,
            // 20: the closest redeclaration is what the generated member must
            //     override — a final override mid-chain conflicts.
            """
            package s20
            open class Base { open fun component1(): Int = 1 }
            open class Mid : Base() { final override fun component1(): Int = 2 }
            data class ShadowedByFinal(val field: String) : Mid()
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)

            func componentConflicts(_ path: String) -> [CompilerCore.Diagnostic] {
                diagnosticsForPath(path, in: ctx).filter {
                    $0.severity == .error && $0.code == "KSWIFTK-SEMA-0442"
                }
            }
            func otherErrors(_ path: String) -> [CompilerCore.Diagnostic] {
                diagnosticsForPath(path, in: ctx).filter {
                    $0.severity == .error && $0.code != "KSWIFTK-SEMA-0442"
                }
            }

            let conflicted = [0, 1, 2, 3, 4, 13, 16, 18, 19, 20]
            let clean = [5, 6, 7, 8, 9, 10, 11, 12, 14, 15]

            for index in conflicted {
                let errors = componentConflicts(paths[index])
                #expect(
                    errors.count == 1,
                    "Source \(index) should report exactly one KSWIFTK-SEMA-0442, got: \(diagnosticsForPath(paths[index], in: ctx).map { "\($0.code): \($0.message)" })"
                )
            }
            for index in clean {
                let errors = componentConflicts(paths[index])
                #expect(
                    errors.isEmpty,
                    "Source \(index) should not report KSWIFTK-SEMA-0442, got: \(diagnosticsForPath(paths[index], in: ctx).map { "\($0.code): \($0.message)" })"
                )
            }

            // Source 17 has an arity-mismatched abstract member: no conflict,
            // but the abstract-completeness check must still report it.
            let arityErrors = diagnosticsForPath(paths[17], in: ctx).filter { $0.severity == .error }
            #expect(
                componentConflicts(paths[17]).isEmpty
                    && arityErrors.contains { $0.code == "KSWIFTK-SEMA-ABSTRACT" },
                "Source 17 should report SEMA-ABSTRACT only, got: \(arityErrors.map { "\($0.code): \($0.message)" })"
            )

            // Non-conflict sources must be otherwise error-free.
            for index in clean {
                let errors = otherErrors(paths[index])
                #expect(
                    errors.isEmpty,
                    "Source \(index) should compile without other errors, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }
        }
    }

    @Test
    func testGeneratedComponentNConflictsWithSameClassDeclaration() throws {
        let sources: [String] = [
            """
            data class DuplicateComponent(val field: Int) {
                operator fun component1(): Int = field
            }
            """,
            """
            data class P(var x: Int, var y: Int) {
                operator fun component1() = x
                operator fun component2() = x + 1
            }

            fun destructure() {
                val (a, b) = P(10, 20)
            }
            """,
            """
            data class OverloadedComponent(val field: Int) {
                fun component1(index: Int): Int = field + index
                operator fun component2(): Int = field
            }

            fun destructureOverloadedComponent(value: OverloadedComponent) {
                val (component) = value
            }
            """,
            """
            class NonDataComponent(val field: Int) {
                operator fun component1(): Int = field
            }

            data class UnrelatedDataComponent(val field: Int)

            fun destructureUnrelatedDataComponent(value: UnrelatedDataComponent) {
                val (component) = value
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)

            let duplicateErrors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(
                duplicateErrors.count == 1 && duplicateErrors[0].code == "KSWIFTK-SEMA-0444",
                "A user-declared parameterless component1() must conflict with the generated member, got: \(duplicateErrors.map { "\($0.code): \($0.message)" })"
            )

            let issueReproErrors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(
                issueReproErrors.count == 2 && issueReproErrors.allSatisfy { $0.code == "KSWIFTK-SEMA-0444" },
                "Both conflicting members in the two-property data class should be diagnosed without a destructuring ambiguity, got: \(issueReproErrors.map { "\($0.code): \($0.message)" })"
            )

            for path in paths.dropFirst(2) {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "An overloaded component function or a non-data-class component should remain valid, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }
        }
    }

    @Test
    func testForLoopDestructuringArrayListPairsFromBundledStdlib() throws {
        let source = """
        val alist = arrayListOf(1 to 2, 2 to 3, 3 to 4)

        fun box(): String {
            var result = 0
            for ([i: Int, z: Int] in alist) {
                result += i + z
            }
            return if (result == 15) "OK" else "fail: $result"
        }

        fun withIndexProbe() {
            val arrayList = ArrayList<Int>()
            for ((index, value) in arrayList.withIndex()) {
                println("$index:$value")
            }
        }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "ArrayList destructuring with the bundled stdlib should type-check: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

}

#endif
