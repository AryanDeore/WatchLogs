//
//  MediaRemoteBridge.swift
//  WatchLogs
//
//  Uses the mediaremote-adapter script to fetch now playing JSON.
//

import Foundation

final class MediaRemoteBridge {
    private let perlPath = "/usr/bin/perl"
    private let fileManager = FileManager.default
    private let scriptPath: String
    private let frameworkPath: String

    init(
        scriptPath: String? = nil,
        frameworkPath: String? = nil
    ) {
        let env = ProcessInfo.processInfo.environment
        let resolvedScript = scriptPath
            ?? env["MEDIAREMOTE_ADAPTER_SCRIPT"]
            ?? MediaRemoteBridge.defaultScriptPath()
            ?? "/tmp/mediaremote-adapter/bin/mediaremote-adapter.pl"

        let resolvedFramework = frameworkPath
            ?? env["MEDIAREMOTE_ADAPTER_FRAMEWORK"]
            ?? "/tmp/mediaremote-adapter/build/MediaRemoteAdapter.framework"

        self.scriptPath = resolvedScript
        self.frameworkPath = resolvedFramework

        print("MediaRemoteBridge configured script=\(self.scriptPath)")
        print("MediaRemoteBridge configured framework=\(self.frameworkPath)")
    }

    private static func defaultScriptPath() -> String? {
        guard let base = Bundle.main.resourceURL else { return nil }
        let candidate = base
            .appendingPathComponent("MediaRemoteAdapter", isDirectory: true)
            .appendingPathComponent("mediaremote-adapter.pl")
            .path
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    private func materializedFrameworkPath() -> String {
        let zipPath = Bundle.main.resourceURL?
            .appendingPathComponent("MediaRemoteAdapter", isDirectory: true)
            .appendingPathComponent("MediaRemoteAdapter.framework.zip")
            .path

        guard let zipPath,
              fileManager.fileExists(atPath: zipPath),
              let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return frameworkPath
        }

        let targetDir = supportDir
            .appendingPathComponent("WatchLogs", isDirectory: true)
            .appendingPathComponent("MediaRemoteAdapter", isDirectory: true)
        let destination = targetDir
            .appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)

        if fileManager.fileExists(atPath: destination.path) {
            return destination.path
        }

        do {
            try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", zipPath, targetDir.path]
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0, fileManager.fileExists(atPath: destination.path) {
                return destination.path
            }
        } catch {
            print("MediaRemoteBridge unzip error: \(error.localizedDescription)")
        }

        return frameworkPath
    }

    func fetchNowPlayingInfo(completion: @escaping ([String: Any]?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let resolvedFrameworkPath = self.materializedFrameworkPath()

            process.executableURL = URL(fileURLWithPath: self.perlPath)
            process.arguments = [self.scriptPath, resolvedFrameworkPath, "get"]
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard process.terminationStatus == 0 else {
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                if let errText = String(data: errData, encoding: .utf8), !errText.isEmpty {
                    print("MediaRemoteBridge error: \(errText)")
                }
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            guard
                !outData.isEmpty,
                let json = try? JSONSerialization.jsonObject(with: outData) as? [String: Any]
            else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            DispatchQueue.main.async {
                completion(json)
            }
        }
    }
}
