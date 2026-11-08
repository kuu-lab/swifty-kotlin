import Foundation

/// A resolved Android SDK toolchain: build-tools directory, the platform
/// `android.jar`, and the individual tool paths used by `--emit dex`/`apk`.
package struct AndroidToolchain: Sendable {
    package let sdkRoot: URL
    package let buildToolsDirectory: URL
    package let d8Path: String
    package let aapt2Path: String?
    package let zipalignPath: String?
    package let apksignerPath: String?
    /// `platforms/android-<api>/android.jar`, or nil when no platform is
    /// installed. Used both as the `d8 --lib` bootclasspath and the `aapt2
    /// link -I` framework.
    package let androidJarPath: String?
}

package enum AndroidSDKError: Error, CustomStringConvertible {
    case sdkRootNotFound(String)
    case buildToolsNotFound(String)
    case toolMissing(String)
    case platformNotFound(String)

    package var description: String {
        switch self {
        case let .sdkRootNotFound(detail):
            "Android SDK not found. \(detail) Set --android-sdk or ANDROID_HOME/ANDROID_SDK_ROOT."
        case let .buildToolsNotFound(detail):
            "Android SDK build-tools not found. \(detail) Install a build-tools package via sdkmanager."
        case let .toolMissing(tool):
            "Android SDK tool '\(tool)' is missing from the selected build-tools directory."
        case let .platformNotFound(detail):
            "Android SDK platform not found. \(detail) Install a platform via sdkmanager."
        }
    }
}

/// Locates the Android SDK, a build-tools version, and a platform
/// `android.jar` for `--emit dex`/`apk`. Resolution order for the SDK root:
/// `--android-sdk`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, then the platform
/// default install location.
package enum AndroidSDKLocator {
    package static func locate(
        sdkPath: String?,
        buildToolsVersion: String?,
        compileSdk: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> AndroidToolchain {
        let root = try resolveSDKRoot(sdkPath: sdkPath, environment: environment, homeDirectory: homeDirectory)
        let buildTools = try resolveBuildTools(
            sdkRoot: root, version: buildToolsVersion
        )
        let androidJar = try resolveAndroidJar(
            sdkRoot: root, compileSdk: compileSdk
        )
        let d8 = toolPath(in: buildTools, named: "d8")
        guard FileManager.default.isExecutableFile(atPath: d8) else {
            throw AndroidSDKError.toolMissing("d8")
        }
        return AndroidToolchain(
            sdkRoot: root,
            buildToolsDirectory: buildTools,
            d8Path: d8,
            aapt2Path: optionalToolPath(in: buildTools, named: "aapt2"),
            zipalignPath: optionalToolPath(in: buildTools, named: "zipalign"),
            apksignerPath: optionalToolPath(in: buildTools, named: "apksigner"),
            androidJarPath: androidJar
        )
    }

    /// The platform `android.jar` alone, without requiring build-tools. Used
    /// by the JVM frontend to inject the Android framework onto the classpath
    /// before codegen runs.
    package static func androidJarPath(
        sdkPath: String?,
        compileSdk: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> String {
        let root = try resolveSDKRoot(sdkPath: sdkPath, environment: environment, homeDirectory: homeDirectory)
        guard let jar = try resolveAndroidJar(sdkRoot: root, compileSdk: compileSdk) else {
            throw AndroidSDKError.platformNotFound(
                "No platforms/android-*/android.jar under \(root.path)."
            )
        }
        return jar
    }

    private static func resolveSDKRoot(
        sdkPath: String?,
        environment: [String: String],
        homeDirectory: URL
    ) throws -> URL {
        var candidates: [String] = []
        if let sdkPath, !sdkPath.isEmpty { candidates.append(sdkPath) }
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let value = environment[key], !value.isEmpty { candidates.append(value) }
        }
        #if os(macOS)
        candidates.append(homeDirectory.appendingPathComponent("Library/Android/sdk").path)
        #elseif os(Linux)
        candidates.append(homeDirectory.appendingPathComponent("Android/Sdk").path)
        #elseif os(Windows)
        if let localAppData = environment["LOCALAPPDATA"], !localAppData.isEmpty {
            candidates.append(localAppData + "/Android/Sdk")
        }
        #endif
        let fileManager = FileManager.default
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            let url = URL(fileURLWithPath: candidate).standardizedFileURL
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { continue }
            // A real SDK root has build-tools and/or platforms subdirectories.
            let hasBuildTools = fileManager.fileExists(
                atPath: url.appendingPathComponent("build-tools").path
            )
            let hasPlatforms = fileManager.fileExists(
                atPath: url.appendingPathComponent("platforms").path
            )
            if hasBuildTools || hasPlatforms { return url }
        }
        throw AndroidSDKError.sdkRootNotFound(
            "Checked --android-sdk, ANDROID_HOME, ANDROID_SDK_ROOT, and the default install location."
        )
    }

    private static func resolveBuildTools(sdkRoot: URL, version: String?) throws -> URL {
        let buildToolsRoot = sdkRoot.appendingPathComponent("build-tools", isDirectory: true)
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: buildToolsRoot, includingPropertiesForKeys: nil
        ) else {
            throw AndroidSDKError.buildToolsNotFound("\(buildToolsRoot.path) does not exist.")
        }
        let versions = entries
            .map(\.lastPathComponent)
            .filter { name in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(
                    atPath: buildToolsRoot.appendingPathComponent(name).path,
                    isDirectory: &isDirectory
                ) && isDirectory.boolValue
            }
            .sorted(by: versionDescending)
        if let version {
            guard versions.contains(version) else {
                throw AndroidSDKError.buildToolsNotFound(
                    "Requested version '\(version)' is not installed (have: \(versions.joined(separator: ", ")))."
                )
            }
            return buildToolsRoot.appendingPathComponent(version, isDirectory: true)
        }
        // Prefer the newest version that actually ships d8.
        for candidate in versions {
            let dir = buildToolsRoot.appendingPathComponent(candidate, isDirectory: true)
            if fileManager.isExecutableFile(atPath: dir.appendingPathComponent("d8").path) {
                return dir
            }
        }
        guard let newest = versions.first else {
            throw AndroidSDKError.buildToolsNotFound("\(buildToolsRoot.path) is empty.")
        }
        return buildToolsRoot.appendingPathComponent(newest, isDirectory: true)
    }

    private static func resolveAndroidJar(sdkRoot: URL, compileSdk: String?) throws -> String? {
        let platformsRoot = sdkRoot.appendingPathComponent("platforms", isDirectory: true)
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: platformsRoot, includingPropertiesForKeys: nil
        ) else { return nil }
        var candidates: [(version: String, jar: URL)] = []
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasPrefix("android-"), name.count > "android-".count else { continue }
            let version = String(name.dropFirst("android-".count))
            let jar = entry.appendingPathComponent("android.jar")
            if fileManager.fileExists(atPath: jar.path) {
                candidates.append((version, jar))
            }
        }
        if let compileSdk {
            // Platform directory names vary ("android-36" vs "android-37.0"),
            // so compare the numeric components rather than the raw string.
            guard let match = candidates.first(where: {
                platformVersionMatches($0.version, compileSdk)
            }) else {
                let installed = candidates.map(\.version).sorted(by: versionDescending)
                throw AndroidSDKError.platformNotFound(
                    "Requested compile SDK '\(compileSdk)' is not installed"
                        + (installed.isEmpty ? "." : " (have: \(installed.joined(separator: ", "))).")
                )
            }
            return match.jar.path
        }
        return candidates.max { versionAscending($0.version, $1.version) }?.jar.path
    }

    private static func toolPath(in directory: URL, named name: String) -> String {
        directory.appendingPathComponent(name).path
    }

    private static func optionalToolPath(in directory: URL, named name: String) -> String? {
        let path = toolPath(in: directory, named: name)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// Dotted numeric version comparison: "36.0.0" > "34.0.0" > "30.0.3",
    /// "37.0" > "36". Non-numeric components sort below numeric ones.
    /// True when two platform version strings denote the same API level:
    /// exact match, or equal after dropping trailing ".0" components
    /// ("37" matches "37.0", but "36" does not match "36.1").
    private static func platformVersionMatches(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        func normalized(_ value: String) -> [Int] {
            var parts = value.split(separator: ".").map { Int($0) ?? -1 }
            while parts.last == 0 { parts.removeLast() }
            return parts
        }
        return normalized(lhs) == normalized(rhs)
    }

    private static func versionDescending(_ lhs: String, _ rhs: String) -> Bool {
        versionAscending(rhs, lhs)
    }

    private static func versionAscending(_ lhs: String, _ rhs: String) -> Bool {
        let l = lhs.split(separator: ".").map { Int($0) ?? -1 }
        let r = rhs.split(separator: ".").map { Int($0) ?? -1 }
        for index in 0..<max(l.count, r.count) {
            let lv = index < l.count ? l[index] : -1
            let rv = index < r.count ? r[index] : -1
            if lv != rv { return lv < rv }
        }
        return lhs < rhs
    }
}
