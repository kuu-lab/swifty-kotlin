#if canImport(Testing)
@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite
struct MutableLocalAssignmentFlowRefinementTests {
    private func context(_ source: String) throws -> CompilationContext {
        TestStdlibCache.shared.prepare()
        _ = try #require(CompilerOptions.defaultStdlibLibraryPath, "Expected a fresh shared stdlib artifact")
        return makeContextFromSource(source, allowDefaultStdlibLibrary: true)
    }

    @Test func inferredMutableLocalKeepsTheDeclaredTypeOfASmartCastInitializer() throws {
        let ctx = try context("""
        open class PsiElement { open val parent: PsiElement get() = this }
        class Child(override val parent: PsiElement) : PsiElement()
        fun widen(element: PsiElement) {
            if (element is Child) {
                var parent = element
                parent = parent.parent
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func inferredMutableLocalRetainsExplicitAndPreSmartCastControls() throws {
        let ctx = try context("""
        open class PsiElement { open val parent: PsiElement get() = this }
        class Child(override val parent: PsiElement) : PsiElement()
        fun explicit(element: PsiElement) {
            if (element is Child) {
                var parent: PsiElement = element
                parent = parent.parent
            }
        }
        fun initializedBeforeSmartCast(element: PsiElement) {
            var parent = element
            if (element is Child) parent = parent.parent
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func explicitNarrowMutableLocalStillRejectsParentTypeReassignment() throws {
        let ctx = try context("""
        open class PsiElement { open val parent: PsiElement get() = this }
        class Child(override val parent: PsiElement) : PsiElement()
        fun reject(element: PsiElement) {
            if (element is Child) {
                var parent: Child = element
                parent = element.parent
            }
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test func refinesComparableLocalFromArrayElementInsideBranch() throws {
        let ctx = try context("""
        fun <T : Comparable<T>> swapIfNeeded(array: Array<T>) {
            var temp: Comparable<T>
            if (array[0] > array[1]) {
                temp = array[0]
                array[0] = array[1]
                array[1] = temp
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func acceptsTypeParameterLocalControl() throws {
        let ctx = try context("""
        fun <T : Comparable<T>> swapIfNeeded(array: Array<T>) {
            var temp: T
            if (array[0] > array[1]) {
                temp = array[0]
                array[0] = array[1]
                array[1] = temp
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func rejectsExplicitComparableValueAsArrayElement() throws {
        let ctx = try context("""
        fun <T : Comparable<T>> reject(array: Array<T>, comparable: Comparable<T>) {
            array[0] = comparable
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test func doesNotLeakBranchAssignmentRefinementPastMerge() throws {
        let ctx = try context("""
        fun <T : Comparable<T>> rejectAfterMerge(array: Array<T>, flag: Boolean) {
            var temp: Comparable<T> = array[0]
            if (flag) temp = array[1]
            array[0] = temp
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test func broadReassignmentClearsBranchLocalRefinement() throws {
        let ctx = try context("""
        fun <T : Comparable<T>> rejectAfterReassignment(
            array: Array<T>, comparable: Comparable<T>, flag: Boolean
        ) {
            var temp: Comparable<T> = array[0]
            if (flag) {
                temp = array[0]
                temp = comparable
                array[0] = temp
            }
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }
}
#endif
