@testable import CompilerBackend
import Foundation
import Testing

struct MacOSLinkerPlanTests {
    @Test
    func decodesQuotedArgumentsWithoutShellExpansion() {
        #expect(MacOSLinkerPlan.tokenize(#"'/a path/clang' a\ b "quoted \"text\"" '$(echo unsafe)' ''"#) ==
            ["/a path/clang", "a b", "quoted \"text\"", "$(echo unsafe)", ""])
        #expect(MacOSLinkerPlan.tokenize("'unfinished") == nil)
        #expect(MacOSLinkerPlan.tokenize("unfinished\\") == nil)
    }

    @Test
    func rejectsMultiJobAndResponseFilePlans() {
        let job = "/usr/bin/clang /dev/null -o /__kswiftk_link_output__"
        #expect(MacOSLinkerPlan.parse(job + "\n/usr/bin/dsymutil output", cacheKey: "key") == nil)
        #expect(MacOSLinkerPlan.parse(job + " @args", cacheKey: "key") == nil)
        #expect(MacOSLinkerPlan.parse(job.replacingOccurrences(of: "clang", with: "other"), cacheKey: "key") == nil)
    }

    @Test
    func toolchainEnvironmentAndDeploymentTargetInvalidateIdentity() {
        let args = ["-target", "arm64-apple-macosx11.0"]
        let key = MacOSLinkerPlan.cacheIdentity(swiftcPath: "/usr/bin/swiftc", driverArguments: args, environment: [:])
        for name in ["DEVELOPER_DIR", "TOOLCHAINS", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET", "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC"] {
            #expect(key != MacOSLinkerPlan.cacheIdentity(
                swiftcPath: "/usr/bin/swiftc", driverArguments: args, environment: [name: "changed"]
            ))
        }
        #expect(key != MacOSLinkerPlan.cacheIdentity(
            swiftcPath: "/usr/bin/swiftc", driverArguments: ["-target", "x86_64-apple-macosx14.0"], environment: [:]
        ))
    }

    @Test
    func extractsForceLoadedPathsAndRejectsUnmodelledShapes() {
        func plan(_ arguments: [String]) -> MacOSLinkerPlan {
            MacOSLinkerPlan(cacheKey: "key", executable: "/usr/bin/clang", arguments: arguments, dependencies: [:])
        }
        #expect(plan(["-force_load", "/a/compat.a", "-dead_strip"]).forceLoadedPaths == ["/a/compat.a"])
        #expect(plan(["a.o", "-force_load", "/a.a", "-force_load", "/b.a"]).forceLoadedPaths == ["/a.a", "/b.a"])
        #expect(plan(["-dead_strip"]).forceLoadedPaths == [])
        // A flag without an absolute-path argument is a shape we do not
        // rewrite: extraction reports nil and the pair stays in place.
        #expect(plan(["-force_load", "relative.a"]).forceLoadedPaths == nil)
        #expect(plan(["-force_load"]).forceLoadedPaths == nil)
    }

    @Test
    func linkArgumentsCanDropForceLoadPairs() {
        let plan = MacOSLinkerPlan(
            cacheKey: "key", executable: "/usr/bin/clang",
            arguments: ["-force_load", "/a.a", "-Xlinker", "-dead_strip", "-o", "/__kswiftk_link_output__"],
            dependencies: [:]
        )
        #expect(plan.linkArguments(inputs: ["u.o"], output: "out", libraryPaths: [], libraries: [], droppingForceLoads: true) ==
            ["u.o", "-Xlinker", "-dead_strip", "-o", "out"])
        #expect(plan.linkArguments(inputs: ["u.o"], output: "out", libraryPaths: [], libraries: []) ==
            ["u.o", "-force_load", "/a.a", "-Xlinker", "-dead_strip", "-o", "out"])
    }

    #if os(macOS)
    @Test
    func reusesPersistedPlanAndInvalidatesChangedArchiveAndCorruptCache() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("compatibility archive.a")
        try Data([1]).write(to: archive)
        let output = "/usr/bin/clang /dev/null -force_load '\(archive.path)' -Xlinker -dead_strip -o /__kswiftk_link_output__"
        let cache = directory.appendingPathComponent("plans")
        var loads = 0
        func load() throws -> MacOSLinkerPlan? {
            try MacOSLinkerPlan.load(swiftcPath: "/usr/bin/swiftc", driverArguments: [], cacheDirectory: cache, environment: [:]) {
                loads += 1
                return output
            }
        }
        let first = try #require(try load())
        let second = try #require(try load())
        #expect(loads == 1)
        #expect(first.arguments == second.arguments)
        let arguments = second.linkArguments(inputs: ["a.o", "b.o"], output: "app with spaces", libraryPaths: ["/custom"], libraries: ["sqlite3"])
        #expect(Array(arguments.prefix(2)) == ["a.o", "b.o"])
        #expect(arguments.contains(archive.path))
        #expect(arguments.contains("app with spaces"))
        #expect(Array(arguments.suffix(2)) == ["-L/custom", "-lsqlite3"])
        #expect(!arguments.contains("/dev/null"))
        try Data([1, 2]).write(to: archive)
        _ = try load()
        #expect(loads == 2)
        let cacheFile = try #require(try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil).first)
        try Data("corrupt".utf8).write(to: cacheFile)
        _ = try load()
        #expect(loads == 3)
        var invalid = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: cacheFile)) as? [String: Any])
        invalid["arguments"] = [String]()
        try JSONSerialization.data(withJSONObject: invalid).write(to: cacheFile)
        _ = try load()
        #expect(loads == 4)
        try FileManager.default.removeItem(at: archive)
        #expect(try load() == nil)
        #expect(loads == 5)
    }
    #endif
}
