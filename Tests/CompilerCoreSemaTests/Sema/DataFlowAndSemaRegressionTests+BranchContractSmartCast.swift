#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

// MARK: - Smart-cast persistence across later flow splits in a branch
//
// Targets: Sema/DataFlow/Analysis.swift `DataFlowState.includingMembers`
//          TypeCheck/CallTypeChecker+TypeConstructionHelpers.swift `applyContractEffects`
//
// KUU-3928: `ctx.flowState` is a snapshot taken at the entry of a `then`/`else`
// branch (or loop body). A narrowing applied inside the branch — `require`/`check`
// contracts, an `is` check — writes only into `locals`. A later flow split in the
// same branch (another contract call, a nested `if`/`when`) rebuilt its base from
// the stale branch-entry entry via `includingMembers`, and applying the split
// result back to `locals` overwrote the refined type, so a valid
// `source.position = position` on the smart-cast receiver reported SEMA-0022
// (okio FileHandle.kt).

extension DataFlowAndSemaRegressionTests {

    private static let smartCastPersistenceSources: [String] = [
        // sample0 — the ticket's minimal repro: `require` narrows `source`,
        // then `check` splits flow again and must keep the refinement.
        """
        package sample0
        interface Source
        class RealBufferedSource(val source: Source, val buffer: Long) : Source

        abstract class FileHandle {
            fun position(source: Source): Long = 0
            private class FileHandleSource(
                val fileHandle: FileHandle,
                var position: Long,
                var closed: Boolean = false
            ) : Source
            fun reposition(source: Source, position: Long) {
                if (source is RealBufferedSource) {
                    val fileHandleSource = source.source
                    require(fileHandleSource is FileHandleSource && fileHandleSource.fileHandle === this) { "bad" }
                    fileHandleSource.position = position
                } else {
                    require(source is FileHandleSource && source.fileHandle === this) { "bad" }
                    check(!source.closed) { "closed" }
                    source.position = position
                }
            }
        }
        """,
        // sample1 — a plain `if` split after the contract narrowing must not
        // reset the refined type either (same stale-base path).
        """
        package sample1
        interface Source
        class RealBufferedSource(val source: Source) : Source

        abstract class FileHandle {
            private class FileHandleSource(
                val fileHandle: FileHandle,
                var position: Long,
                var closed: Boolean = false
            ) : Source
            fun reposition(source: Source, position: Long) {
                if (source is RealBufferedSource) {
                } else {
                    require(source is FileHandleSource) { "bad" }
                    if (source.closed) {
                        source.position = position
                    }
                    source.position = position
                }
            }
        }
        """,
        // sample2 — `returns() implies` contracts (`requireNotNull`) take the
        // `.normally` implication path, which must likewise start from the
        // locals-inclusive state.
        """
        package sample2
        interface Source
        class RealBufferedSource(val source: Source) : Source

        abstract class FileHandle {
            private class FileHandleSource(
                val fileHandle: FileHandle,
                var position: Long
            ) : Source
            fun reposition(source: Source, position: Long, token: Any?) {
                if (source is RealBufferedSource) {
                } else {
                    require(source is FileHandleSource) { "bad" }
                    requireNotNull(token)
                    source.position = position
                }
            }
        }
        """,
        // sample3 — the `then` branch carries the same snapshot: narrowing
        // inside it must survive a later split too.
        """
        package sample3
        interface Source
        class RealBufferedSource(val source: Source) : Source

        abstract class FileHandle {
            private class FileHandleSource(
                val fileHandle: FileHandle,
                var position: Long
            ) : Source
            fun reposition(source: Source, position: Long) {
                if (source is RealBufferedSource) {
                    val inner = source.source
                    require(inner is FileHandleSource) { "bad" }
                    check(true) { "x" }
                    inner.position = position
                } else {
                }
            }
        }
        """,
        // sample4 — negative control: a real reassignment still legitimately
        // drops the smart cast, so `s.position` on the widened `s` stays
        // unresolved (SEMA-0022 is expected here).
        """
        package sample4
        interface Source
        class RealBufferedSource(val source: Source) : Source

        abstract class FileHandle {
            private class FileHandleSource(
                val fileHandle: FileHandle,
                var position: Long
            ) : Source
            fun reposition(source: Source, position: Long, other: Source) {
                var s = source
                if (s is RealBufferedSource) {
                } else {
                    require(s is FileHandleSource) { "bad" }
                    check(true) { "x" }
                    s = other
                    s.position = position
                }
            }
        }
        """,
    ]

    private static nonisolated(unsafe) var _smartCastPersistenceCtx: (CompilationContext, [String])?

    private func smartCastPersistenceCtx() throws -> (CompilationContext, [String]) {
        if let cached = Self._smartCastPersistenceCtx { return cached }
        var result: (CompilationContext, [String])?
        try withTemporaryFiles(contents: Self.smartCastPersistenceSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (ctx, paths)
        }
        let ctx = try #require(result)
        Self._smartCastPersistenceCtx = ctx
        return ctx
    }

    @Test
    func contractCallInElseBranchKeepsEarlierSmartCast() throws {
        let (ctx, paths) = try smartCastPersistenceCtx()
        for path in paths.dropLast() {
            let diagnostics = diagnosticsForPath(path, in: ctx)
            #expect(diagnostics.isEmpty, "Unexpected diagnostics: \(diagnostics.map(\.code))")
        }
        // sample4 is the negative control: the write legitimately invalidated
        // the cast, so the unresolved-member diagnostic must still fire.
        let reassignedDiagnostics = diagnosticsForPath(paths[4], in: ctx)
        #expect(
            reassignedDiagnostics.contains { $0.code == "KSWIFTK-SEMA-0022" },
            "Reassignment must keep reporting SEMA-0022: \(reassignedDiagnostics.map(\.code))"
        )
    }
}
#endif
