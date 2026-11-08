#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite("Driver.AndroidSDKLocator")
struct AndroidSDKLocatorTests {
    private func makeSDK(
        _ body: (URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-sdk-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func makeBuildTools(_ root: URL, _ version: String, withD8: Bool = true) throws {
        let dir = root.appendingPathComponent("build-tools/\(version)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if withD8 {
            let d8 = dir.appendingPathComponent("d8")
            try Data("#!/bin/sh\n".utf8).write(to: d8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d8.path)
        }
    }

    private func makePlatform(_ root: URL, _ api: String) throws {
        let dir = root.appendingPathComponent("platforms/android-\(api)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("jar".utf8).write(to: dir.appendingPathComponent("android.jar"))
    }

    @Test
    func locatesNewestBuildToolsAndPlatform() throws {
        try makeSDK { root in
            try makeBuildTools(root, "34.0.0")
            try makeBuildTools(root, "36.0.0")
            try makeBuildTools(root, "30.0.3", withD8: false)
            try makePlatform(root, "34")
            try makePlatform(root, "36")

            let toolchain = try AndroidSDKLocator.locate(
                sdkPath: root.path, buildToolsVersion: nil, compileSdk: nil,
                environment: [:]
            )
            #expect(toolchain.buildToolsDirectory.lastPathComponent == "36.0.0")
            #expect(toolchain.d8Path.hasSuffix("build-tools/36.0.0/d8"))
            #expect(toolchain.androidJarPath?.hasSuffix("platforms/android-36/android.jar") == true)
        }
    }

    @Test
    func honorsExplicitVersions() throws {
        try makeSDK { root in
            try makeBuildTools(root, "34.0.0")
            try makeBuildTools(root, "36.0.0")
            try makePlatform(root, "34")
            try makePlatform(root, "36")

            let toolchain = try AndroidSDKLocator.locate(
                sdkPath: root.path, buildToolsVersion: "34.0.0", compileSdk: "34",
                environment: [:]
            )
            #expect(toolchain.buildToolsDirectory.lastPathComponent == "34.0.0")
            #expect(toolchain.androidJarPath?.hasSuffix("platforms/android-34/android.jar") == true)

            #expect(throws: AndroidSDKError.self) {
                try AndroidSDKLocator.locate(
                    sdkPath: root.path, buildToolsVersion: "99.0.0", compileSdk: nil,
                    environment: [:]
                )
            }
            #expect(throws: AndroidSDKError.self) {
                try AndroidSDKLocator.locate(
                    sdkPath: root.path, buildToolsVersion: nil, compileSdk: "99",
                    environment: [:]
                )
            }
        }
    }

    @Test
    func resolvesSDKRootFromEnvironment() throws {
        try makeSDK { root in
            try makeBuildTools(root, "36.0.0")
            try makePlatform(root, "36")
            let jar = try AndroidSDKLocator.androidJarPath(
                sdkPath: nil, compileSdk: nil,
                environment: ["ANDROID_HOME": root.path],
                homeDirectory: FileManager.default.temporaryDirectory
            )
            #expect(jar.hasSuffix("platforms/android-36/android.jar"))
        }
    }

    @Test
    func reportsMissingSDKAndTools() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-sdk-empty-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        #expect(throws: AndroidSDKError.self) {
            try AndroidSDKLocator.locate(
                sdkPath: empty.path, buildToolsVersion: nil, compileSdk: nil,
                environment: [:], homeDirectory: empty
            )
        }
        try makeSDK { root in
            // platforms only, no build-tools
            try makePlatform(root, "36")
            #expect(throws: AndroidSDKError.self) {
                try AndroidSDKLocator.locate(
                    sdkPath: root.path, buildToolsVersion: nil, compileSdk: nil,
                    environment: [:]
                )
            }
            // build-tools only, no platform: androidJarPath fails
            try? FileManager.default.removeItem(at: root.appendingPathComponent("platforms"))
            try makeBuildTools(root, "36.0.0")
            #expect(throws: AndroidSDKError.self) {
                try AndroidSDKLocator.androidJarPath(
                    sdkPath: root.path, compileSdk: nil, environment: [:]
                )
            }
        }
    }
}
#endif
