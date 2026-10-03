// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

public func assertMacroExpansion(
  _ source: String,
  expandedSource: String,
  macros: [String: Macro.Type],
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  line: UInt = #line,
  column: UInt = #column
) {
  SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion(
    source,
    expandedSource: expandedSource,
    macroSpecs: macros.mapValues { MacroSpec(type: $0) },
    indentationWidth: .spaces(2),
    failureHandler: { failure in
      Issue.record(
        Comment(rawValue: failure.message),
        sourceLocation: SourceLocation(
          fileID: failure.location.fileID,
          filePath: failure.location.filePath,
          line: failure.location.line,
          column: failure.location.column
        )
      )
    },
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}
