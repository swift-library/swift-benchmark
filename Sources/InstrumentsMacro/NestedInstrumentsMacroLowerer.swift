// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import SwiftSyntax

final class NestedInstrumentsMacroLowerer: SyntaxRewriter {
  private var error: Error?

  init() {
    super.init(viewMode: .sourceAccurate)
  }

  func lower(_ closure: ClosureExprSyntax) throws -> ClosureExprSyntax {
    let rewritten = rewrite(Syntax(closure))
    if let error {
      throw error
    }
    return rewritten.as(ClosureExprSyntax.self) ?? closure
  }

  override func visit(_ node: TryExprSyntax) -> ExprSyntax {
    guard attemptLowering else {
      return ExprSyntax(node)
    }

    do {
      if let span = node.expression.as(MacroExpansionExprSyntax.self),
        isSpanMacro(span)
      {
        return try wrapTry(node, around: lowerSpan(span, invocation: "try "))
      }

      if let awaitExpr = node.expression.as(AwaitExprSyntax.self),
        let span = awaitExpr.expression.as(MacroExpansionExprSyntax.self),
        isSpanMacro(span)
      {
        return try wrapTry(
          node, isAwaiting: true, around: lowerSpan(span, invocation: "try await "))
      }
    } catch {
      record(error)
      return ExprSyntax(node)
    }

    return super.visit(node)
  }

  override func visit(_ node: AwaitExprSyntax) -> ExprSyntax {
    do {
      if let span = node.expression.as(MacroExpansionExprSyntax.self),
        isSpanMacro(span)
      {
        return try wrapAwait(around: lowerSpan(span, invocation: "await "))
      }

      if let tryExpr = node.expression.as(TryExprSyntax.self),
        let span = tryExpr.expression.as(MacroExpansionExprSyntax.self),
        isSpanMacro(span)
      {
        return try wrapAwait(tryExpr, around: lowerSpan(span, invocation: "try await "))
      }
    } catch {
      record(error)
      return ExprSyntax(node)
    }

    return super.visit(node)
  }

  override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
    do {
      if isSpanMacro(node) {
        return try lowerSpan(node, invocation: "")
      }

      if isEventMacro(node) {
        return try InstrumentsMacroExpansion.makeEventExpression(from: node)
      }
    } catch {
      record(error)
      return ExprSyntax(node)
    }

    return super.visit(node)
  }

  private var attemptLowering: Bool {
    error == nil
  }

  private func record(_ error: Error) {
    if self.error == nil {
      self.error = error
    }
  }

  private func isSpanMacro(_ node: MacroExpansionExprSyntax) -> Bool {
    node.macroName.text == "span"
  }

  private func isEventMacro(_ node: MacroExpansionExprSyntax) -> Bool {
    node.macroName.text == "event"
  }

  private func lowerSpan(
    _ node: MacroExpansionExprSyntax,
    invocation: String
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeSpanExpression(from: node, invocation: invocation)
  }

  private func wrapTry(
    _ node: TryExprSyntax,
    isAwaiting: Bool = false,
    around expression: ExprSyntax
  ) -> ExprSyntax {
    let marker = node.questionOrExclamationMark?.text ?? ""
    let awaitPrefix = isAwaiting ? "await " : ""
    return "\(raw: "try\(marker) \(awaitPrefix)")\(expression)"
  }

  private func wrapAwait(
    around expression: ExprSyntax
  ) -> ExprSyntax {
    "\(raw: "await ")\(expression)"
  }

  private func wrapAwait(
    _ tryExpr: TryExprSyntax,
    around expression: ExprSyntax
  ) -> ExprSyntax {
    let marker = tryExpr.questionOrExclamationMark?.text ?? ""
    return "\(raw: "await try\(marker) ")\(expression)"
  }
}
