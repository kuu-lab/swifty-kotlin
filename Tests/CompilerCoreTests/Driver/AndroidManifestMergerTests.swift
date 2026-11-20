#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite("Driver.AndroidManifestMerger")
struct AndroidManifestMergerTests {
    private func parse(_ text: String) throws -> AndroidXMLElement {
        try AndroidXMLElement.parse(Data(text.utf8))
    }

    private func names(_ element: AndroidXMLElement?, _ tag: String) -> [String] {
        element?.children(tag).compactMap { $0[attribute: "android:name"] } ?? []
    }

    @Test
    func mergesLibraryComponentsLikeAGP() throws {
        let app = try parse("""
            <manifest xmlns:android="http://schemas.android.com/apk/res/android"
                      xmlns:tools="http://schemas.android.com/tools">
                <application android:label="App">
                    <activity android:name=".MainActivity" android:exported="true" />
                    <provider android:name="androidx.startup.InitializationProvider"
                              android:authorities="${applicationId}.androidx-startup" tools:node="merge">
                        <meta-data android:name="lib.Unwanted" tools:node="remove" />
                    </provider>
                </application>
            </manifest>
            """)
        let core = try parse("""
            <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="androidx.core">
                <uses-sdk android:minSdkVersion="21" />
                <permission android:name="${applicationId}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
                            android:protectionLevel="signature" />
                <uses-permission android:name="${applicationId}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" />
                <application android:appComponentFactory="androidx.core.app.CoreComponentFactory"
                             android:label="Library label" />
            </manifest>
            """)
        let emoji = try parse("""
            <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="androidx.emoji2">
                <application>
                    <provider android:name="androidx.startup.InitializationProvider"
                              android:authorities="${applicationId}.androidx-startup" android:exported="false">
                        <meta-data android:name="androidx.emoji2.text.EmojiCompatInitializer" android:value="androidx.startup" />
                        <meta-data android:name="lib.Unwanted" android:value="androidx.startup" />
                    </provider>
                    <service android:name=".text.Worker" />
                </application>
            </manifest>
            """)
        let lifecycle = try parse("""
            <manifest xmlns:android="http://schemas.android.com/apk/res/android"
                      xmlns:tools="http://schemas.android.com/tools" package="androidx.lifecycle">
                <application>
                    <provider android:name="androidx.startup.InitializationProvider"
                              android:authorities="${applicationId}.androidx-startup" tools:node="merge">
                        <meta-data android:name="androidx.lifecycle.ProcessLifecycleInitializer" android:value="androidx.startup" />
                    </provider>
                </application>
            </manifest>
            """)

        let merged = AndroidManifestMerger.merge(
            app: app, namespace: "org.example", applicationID: "org.example.app",
            libraries: [("androidx.core", core), ("androidx.emoji2", emoji), ("androidx.lifecycle", lifecycle)]
        )

        #expect(merged[attribute: "package"] == "org.example")
        #expect(merged.child("uses-sdk") == nil)
        #expect(names(merged, "permission") == ["org.example.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"])
        #expect(names(merged, "uses-permission") == ["org.example.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"])
        let application = try #require(merged.child("application"))
        // The app's attributes win; missing ones come from libraries.
        #expect(application[attribute: "android:label"] == "App")
        #expect(application[attribute: "android:appComponentFactory"] == "androidx.core.app.CoreComponentFactory")
        #expect(names(application, "activity") == ["org.example.MainActivity"])
        #expect(names(application, "service") == ["androidx.emoji2.text.Worker"])
        // One provider collects every library's initializer, minus the removed one.
        let providers = application.children("provider")
        try #require(providers.count == 1)
        #expect(providers[0][attribute: "android:authorities"] == "org.example.app.androidx-startup")
        #expect(providers[0][attribute: "android:exported"] == "false")
        #expect(names(providers[0], "meta-data") == [
            "androidx.emoji2.text.EmojiCompatInitializer", "androidx.lifecycle.ProcessLifecycleInitializer",
        ])
        let text = merged.serialized()
        #expect(!text.contains("tools:"))
        // The serialized manifest (what aapt2 reads) parses back with the merged components.
        let reparsed = try parse(text)
        #expect(names(reparsed.child("application"), "provider") == ["androidx.startup.InitializationProvider"])
        #expect(reparsed.attributes.first?.0 == "xmlns:android")
    }

    @Test
    func parsesTheXMLThatPOMsAndManifestsUse() throws {
        let root = try parse("""
            \u{FEFF}<?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE project>
            <!-- licence header -->
            <project xmlns="http://maven.apache.org/POM/4.0.0" attr='single &amp; "quoted"'>
              <name>A &lt;b&gt; &#65;&#x42;</name>
              <description><![CDATA[raw <text> & more]]></description>
              <?ignored instruction?>
              <empty/>
            </project>
            """)
        #expect(root.name == "project")
        #expect(root[attribute: "xmlns"] == "http://maven.apache.org/POM/4.0.0")
        #expect(root[attribute: "attr"] == "single & \"quoted\"")
        #expect(root.value("name") == "A <b> AB")
        #expect(root.value("description") == "raw <text> & more")
        #expect(root.children.map(\.name) == ["name", "description", "empty"])
        for malformed in ["<a><b></a>", "<a>", "", "<a></a><b/>", "<a x=1/>", "<a>&nope;</a>"] {
            #expect(throws: AndroidPackagingError.self) { try parse(malformed) }
        }
    }

    @Test
    func removalsMatchRelativeNamesAndPlaceholders() throws {
        let app = try parse("""
            <manifest xmlns:android="http://schemas.android.com/apk/res/android"
                      xmlns:tools="http://schemas.android.com/tools" package="org.example">
                <application>
                    <activity android:name=".Hidden" tools:node="remove" />
                </application>
                <permission android:name="${applicationId}.DYNAMIC" tools:node="remove" />
            </manifest>
            """)
        let library = try parse("""
            <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="lib">
                <permission android:name="${applicationId}.DYNAMIC" />
                <application><activity android:name="org.example.Hidden" /></application>
            </manifest>
            """)
        let merged = AndroidManifestMerger.merge(
            app: app, namespace: "org.example", applicationID: "org.example.app", libraries: [("lib", library)]
        )
        #expect(merged.children("permission").isEmpty)
        #expect(merged.child("application")?.children("activity").isEmpty == true)
    }

    @Test
    func identicalNamelessElementsAreDeduplicated() throws {
        let app = try parse("""
            <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.example">
                <queries><intent><action android:name="a" /></intent></queries>
            </manifest>
            """)
        let library = try parse("""
            <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="lib">
                <queries><intent><action android:name="a" /></intent><intent><action android:name="b" /></intent></queries>
            </manifest>
            """)
        let merged = AndroidManifestMerger.merge(
            app: app, namespace: "org.example", applicationID: "org.example", libraries: [("lib", library)]
        )
        #expect(merged.children("queries").count == 1)
        #expect(merged.child("queries")?.children("intent").count == 2)
    }
}
#endif
