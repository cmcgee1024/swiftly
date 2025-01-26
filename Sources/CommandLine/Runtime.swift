import Foundation

public enum CommandLineError: Error {
    case invalidArgs
    case errorExit(exitCode: Int32, program: String)
    case unknownVersion
}

#if os(Linux) || os(macOS)

/// Run a program.
///
/// In the case where the command exit with a non-zero exit code a RunProgramError is thrown with
/// the exit code and program information.
///
public func runProgram(_ args: String..., quiet: Bool = false, env: [String: String]? = nil) throws {
    try runProgram([String](args), quiet: quiet, env: env)
}

/// Run a program.
///
/// In the case where the command exit with a non-zero exit code a RunProgramError is thrown with
/// the exit code and program information.
///
public func runProgram(_ args: [String], quiet: Bool = false, env: [String: String]? = nil) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args

    if let env = env {
        process.environment = env
    }

    if quiet {
        process.standardOutput = nil
        process.standardError = nil
    }

    try process.run()
    // Attach this process to our process group so that Ctrl-C and other signals work
    let pgid = tcgetpgrp(STDOUT_FILENO)
    if pgid != -1 {
        tcsetpgrp(STDOUT_FILENO, process.processIdentifier)
    }
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw CommandLineError.errorExit(exitCode: process.terminationStatus, program: args.first!)
    }
}

/// Run a program and capture its output.
///
/// In the case where the command exit with a non-zero exit code a RunProgramError is thrown with
/// the exit code and program information.
///
public func runProgramOutput(_ program: String, _ args: String..., env: [String: String]? = nil) async throws -> String? {
    try await runProgramOutput(program, [String](args), env: env)
}

/// Run a program and capture its output.
///
/// In the case where the command exit with a non-zero exit code a RunProgramError is thrown with
/// the exit code and program information.
///
public func runProgramOutput(_ program: String, _ args: [String], env: [String: String]? = nil) async throws -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [program] + args

    if let env = env {
        process.environment = env
    }

    let outPipe = Pipe()
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardOutput = outPipe

    try process.run()
    // Attach this process to our process group so that Ctrl-C and other signals work
    let pgid = tcgetpgrp(STDOUT_FILENO)
    if pgid != -1 {
        tcsetpgrp(STDOUT_FILENO, process.processIdentifier)
    }
    let outData = try outPipe.fileHandleForReading.readToEnd()

    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw CommandLineError.errorExit(exitCode: process.terminationStatus, program: args.first!)
    }

    if let outData = outData {
        return String(data: outData, encoding: .utf8)
    } else {
        return nil
    }
}

#endif
