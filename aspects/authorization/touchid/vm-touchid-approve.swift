import Darwin
import Dispatch
import Foundation
import LocalAuthentication

let fallbackReason = "Approve a sudo request from the NixOS VM"
let reason = CommandLine.arguments.dropFirst().joined(separator: " ")
let context = LAContext()
var error: NSError?

if #available(macOS 10.12.2, *) {
    context.touchIDAuthenticationAllowableReuseDuration = 0
}

guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
    let message = error?.localizedDescription ?? "Touch ID is unavailable"
    FileHandle.standardError.write(Data("vm-touchid-approve: \(message)\n".utf8))
    Darwin.exit(2)
}

let semaphore = DispatchSemaphore(value: 0)
var approved = false
var failureMessage: String?

context.evaluatePolicy(
    .deviceOwnerAuthenticationWithBiometrics,
    localizedReason: reason.isEmpty ? fallbackReason : reason
) { success, evalError in
    approved = success
    if let evalError, !success {
        failureMessage = evalError.localizedDescription
    }
    semaphore.signal()
}

semaphore.wait()

if approved {
    Darwin.exit(0)
}

if let failureMessage {
    FileHandle.standardError.write(Data("vm-touchid-approve: \(failureMessage)\n".utf8))
}

Darwin.exit(1)
