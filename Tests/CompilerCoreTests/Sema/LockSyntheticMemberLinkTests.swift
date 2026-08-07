#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LockSyntheticMemberLinkTests {

    private func externalLinks(
        for owner: String,
        member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        let fq = ["kotlin", "concurrent", owner, member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    @Test
    func testLockSyntheticMemberLinkTestsInventory() throws {
        let sources: [String] = [
            """
            fun noop() {}
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx
            // KSP-677: Lock.withLock is migrated to Kotlin source
            // (Stdlib/kotlin/concurrent/Lock.kt) delegating to the demoted
            // __kk_lock_withLock bridge, so it is no longer a synthetic member.

            // === testReadWriteLockMembersHaveCorrectExternalLinks ===
            do {

                let factoryFq = ["kotlin", "concurrent", "readWriteLock"].map { interner.intern($0) }
                let factoryLinks = sema.symbols.lookupAll(fqName: factoryFq).compactMap { sema.symbols.externalLinkName(for: $0) }
                let hasFactory = factoryLinks.contains("kk_read_write_lock_create")
                #expect(hasFactory, "readWriteLock() stub missing")

                let readLinks = externalLinks(for: "ReentrantReadWriteLock", member: "read", sema: sema, interner: interner)
                let hasRead = readLinks.contains("kk_read_write_lock_read")
                #expect(hasRead, "ReentrantReadWriteLock.read() stub missing")

                let writeLinks = externalLinks(for: "ReentrantReadWriteLock", member: "write", sema: sema, interner: interner)
                let hasWrite = writeLinks.contains("kk_read_write_lock_write")
                #expect(hasWrite, "ReentrantReadWriteLock.write() stub missing")
            }
        }
    }

}
#endif
