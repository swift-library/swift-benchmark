// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import _BenchmarkDiscoveryCore

@main
struct BenchmarkDiscoveryTool {
  static func main() {
    BenchmarkDiscoveryToolDriver.run(
      arguments: Array(CommandLine.arguments.dropFirst())
    )
  }
}
