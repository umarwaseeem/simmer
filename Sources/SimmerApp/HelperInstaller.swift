import Foundation
import AppKit

/// Runs the bundled install / uninstall scripts as root through an admin-rights AppleScript prompt.
enum HelperInstaller {
    enum Outcome { case success, cancelled, failed(String) }

    static func scriptURL(_ name: String) -> URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name),
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    static var isBundled: Bool { scriptURL("install-helper.sh") != nil }

    static func install() -> Outcome {
        guard let script = scriptURL("install-helper.sh") else {
            return .failed("install-helper.sh is missing. Build the app with scripts/build.sh and run it from dist/Simmer.app.")
        }
        return runAsAdmin([script.path, Bundle.main.bundlePath])
    }

    static func uninstall(purge: Bool = false) -> Outcome {
        guard let script = scriptURL("uninstall-helper.sh") else {
            return .failed("uninstall-helper.sh is missing from the app bundle.")
        }
        return runAsAdmin([script.path] + (purge ? ["--purge"] : []))
    }

    /// Escapes a Swift string for use inside an AppleScript string literal.
    private static func appleScriptLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// `do shell script "'<path>' '<arg>'" with administrator privileges`, with each word shell-quoted.
    private static func runAsAdmin(_ words: [String]) -> Outcome {
        let command = words.map { "quoted form of \(appleScriptLiteral($0))" }.joined(separator: " & \" \" & ")
        let source = "do shell script \(command) with administrator privileges"
        guard let script = NSAppleScript(source: source) else { return .failed("Could not create the AppleScript.") }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return .success }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return .cancelled }
        return .failed((error[NSAppleScript.errorMessage] as? String) ?? "The script failed.")
    }
}
