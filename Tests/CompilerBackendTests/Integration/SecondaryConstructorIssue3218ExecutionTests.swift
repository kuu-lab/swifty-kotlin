#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct SecondaryConstructorIssue3218ExecutionTests {
    @Test
    func secondaryConstructorDefaultsAndSuperArgumentsInitializeFields() throws {
        try assertKotlinOutput(
            try source(named: "kuu_3529_secondary_ctor_default_args.kt"),
            moduleName: "SecondaryConstructorDefaultsAndSuperArguments",
            expected: "abc#efg\nhij#klm#1\nxyz#efg\nxyz#123\nhij#klm2\n123.1#efg\ntest#123\nOK\n"
        )
    }

    @Test
    func genericSecondaryConstructorDelegationInitializesFields() throws {
        try assertKotlinOutput(
            try source(named: "kuu_3529_secondary_ctor_generics.kt"),
            moduleName: "GenericSecondaryConstructorDelegation",
            expected: "1#2\nabc#abc\ndefault#default\nxyz#default\nOK\n"
        )
    }

    @Test
    func bareEarlyReturnLeavesConstructedInstance() throws {
        try assertKotlinOutput(
            try source(named: "kuu_3529_secondary_ctor_early_return.kt"),
            moduleName: "SecondaryConstructorBareEarlyReturn",
            expected: "1\n2\nOK\n"
        )
    }

    private func source(named fileName: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Integration/
            .deletingLastPathComponent() // CompilerBackendTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repository root
        let sourceURL = repositoryRoot.appendingPathComponent("Scripts/diff_cases/\(fileName)")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
#endif
