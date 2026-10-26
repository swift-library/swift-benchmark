// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

/// Captures a child process's standard output and standard error in
/// temporary files.
///
/// A child that prints more than a pipe holds cannot block while its parent
/// waits for it to exit, and nothing has to read while it runs.
package final class ProcessOutputCapture {
  /// Where the child writes its standard output.
  package let output: FileHandle
  /// Where the child writes its standard error.
  package let error: FileHandle
  private let directory: URL

  package init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-output-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let outputURL = directory.appendingPathComponent("stdout")
    let errorURL = directory.appendingPathComponent("stderr")
    _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    _ = FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    output = try FileHandle(forWritingTo: outputURL)
    error = try FileHandle(forWritingTo: errorURL)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  /// What the child wrote to standard output so far.
  package func standardOutput() -> String {
    contents(of: "stdout")
  }

  /// What the child wrote to standard error so far.
  package func standardError() -> String {
    contents(of: "stderr")
  }

  private func contents(of name: String) -> String {
    let data = (try? Data(contentsOf: directory.appendingPathComponent(name))) ?? Data()
    return String(decoding: data, as: UTF8.self)
  }
}
