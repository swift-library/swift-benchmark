// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

/// Text for identifiers built from names, such as step, row and report
/// identifiers.
package enum BenchmarkIdentifier {
  private static let unescaped = CharacterSet.alphanumerics.union(
    CharacterSet(charactersIn: "-_"))

  /// `name` with every character other than a letter, digit, `-` or `_`
  /// percent-encoded.
  ///
  /// Distinct names give distinct components, and a component contains no
  /// other punctuation, so an identifier that joins components with any
  /// other character keeps distinct names distinct.
  package static func component(_ name: String) -> String {
    name.addingPercentEncoding(withAllowedCharacters: unescaped) ?? name
  }
}
