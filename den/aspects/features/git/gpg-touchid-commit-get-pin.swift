import Darwin
import Dispatch
import Foundation
import LocalAuthentication
import Security

let env = ProcessInfo.processInfo.environment
let keychainLabel = (env["GPG_TOUCHID_KEYCHAIN_LABEL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
let fallbackReason = "Unlock the GPG commit signing key"
let promptReason = (env["GPG_TOUCHID_PROMPT_DESC"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
let reason = promptReason.isEmpty ? fallbackReason : promptReason
let context = LAContext()
var error: NSError?

func fail(_ prefix: String, _ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("\(prefix): \(message)\n".utf8))
    Darwin.exit(code)
}

guard !keychainLabel.isEmpty else {
    fail("gpg-touchid-commit-get-pin", "missing GPG_TOUCHID_KEYCHAIN_LABEL", 2)
}

if #available(macOS 10.12.2, *) {
    context.touchIDAuthenticationAllowableReuseDuration = 0
}

guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
    fail("gpg-touchid-commit-get-pin", error?.localizedDescription ?? "Touch ID is unavailable", 2)
}

let semaphore = DispatchSemaphore(value: 0)
var approved = false
var failureMessage: String?
var failureCode: LAError.Code?

context.evaluatePolicy(
    .deviceOwnerAuthenticationWithBiometrics,
    localizedReason: reason
) { success, evalError in
    approved = success
    if let evalError, !success {
        failureMessage = evalError.localizedDescription
        if let laError = evalError as? LAError {
            failureCode = laError.code
        }
    }
    semaphore.signal()
}

semaphore.wait()

if !approved {
    if let failureMessage {
        FileHandle.standardError.write(Data("gpg-touchid-commit-get-pin: \(failureMessage)\n".utf8))
    }
    let isExplicitCancellation = failureCode == .userCancel || failureCode == .userFallback
    Darwin.exit(isExplicitCancellation ? 1 : 2)
}

let query: [CFString: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecAttrService: "GnuPG",
    kSecAttrLabel: keychainLabel,
    kSecMatchLimit: kSecMatchLimitOne,
    kSecReturnData: true,
    kSecUseAuthenticationContext: context,
]

var item: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &item)
guard status == errSecSuccess else {
    let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain lookup failed (\(status))"
    fail("gpg-touchid-commit-get-pin", message, 2)
}

guard let data = item as? Data else {
    fail("gpg-touchid-commit-get-pin", "Keychain lookup returned no data", 2)
}

FileHandle.standardOutput.write(data)
Darwin.exit(0)
