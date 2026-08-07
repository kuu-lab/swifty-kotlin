#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RandomSyntheticLinkTests {
    // MIGRATION-RANDOM-001: nextLong / nextFloat / nextDouble / nextBoolean / nextInt
    // are migrated to Kotlin source. Their synthetic stubs are removed.
    // Tests for those stub-specific external links were deleted in this migration.
}
#endif
