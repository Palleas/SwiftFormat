//
//  Rules.swift
//  SwiftFormat
//
//  Version 0.18
//
//  Created by Nick Lockwood on 21/10/2016.
//  Copyright 2016 Nick Lockwood
//
//  Distributed under the permissive zlib license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/SwiftFormat
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

import Foundation

/// The indenting mode to use for #if/#endif statements
public enum IndentMode: String {
    case indent
    case noindent
    case outdent
}

/// Configuration options for formatting. These aren't actually used by the
/// Formatter class itself, but it makes them available to the format rules.
public struct FormatOptions: CustomStringConvertible {
    public var indent: String
    public var linebreak: String
    public var allowInlineSemicolons: Bool
    public var spaceAroundRangeOperators: Bool
    public var useVoid: Bool
    public var trailingCommas: Bool
    public var indentComments: Bool
    public var truncateBlankLines: Bool
    public var insertBlankLines: Bool
    public var removeBlankLines: Bool
    public var allmanBraces: Bool
    public var stripHeader: Bool
    public var ifdefIndentMode: IndentMode
    public var uppercaseHex: Bool
    public var experimentalRules: Bool
    public var fragment: Bool

    public init(indent: String = "    ",
                linebreak: String = "\n",
                allowInlineSemicolons: Bool = true,
                spaceAroundRangeOperators: Bool = true,
                useVoid: Bool = true,
                trailingCommas: Bool = true,
                indentComments: Bool = true,
                truncateBlankLines: Bool = true,
                insertBlankLines: Bool = true,
                removeBlankLines: Bool = true,
                allmanBraces: Bool = false,
                stripHeader: Bool = false,
                ifdefIndentMode: IndentMode = .indent,
                uppercaseHex: Bool = true,
                experimentalRules: Bool = false,
                fragment: Bool = false) {

        self.indent = indent
        self.linebreak = linebreak
        self.allowInlineSemicolons = allowInlineSemicolons
        self.spaceAroundRangeOperators = spaceAroundRangeOperators
        self.useVoid = useVoid
        self.trailingCommas = trailingCommas
        self.indentComments = indentComments
        self.truncateBlankLines = truncateBlankLines
        self.insertBlankLines = insertBlankLines
        self.removeBlankLines = removeBlankLines
        self.allmanBraces = allmanBraces
        self.stripHeader = stripHeader
        self.ifdefIndentMode = ifdefIndentMode
        self.uppercaseHex = uppercaseHex
        self.experimentalRules = experimentalRules
        self.fragment = fragment
    }

    public var description: String {
        let allowedCharacters = CharacterSet.whitespacesAndNewlines.inverted
        return Mirror(reflecting: self).children.map({
            return "\($0.value);".addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? ""
        }).joined()
    }
}

/// Infer default options by examining the existing source
public func inferOptions(_ tokens: [Token]) -> FormatOptions {
    let formatter = Formatter(tokens)
    var options = FormatOptions()

    options.indent = {
        var indents = [(indent: String, count: Int)]()
        func increment(_ indent: String) {
            for (i, element) in indents.enumerated() {
                if element.indent == indent {
                    indents[i] = (indent, element.count + 1)
                    return
                }
            }
            indents.append((indent, 0))
        }
        formatter.forEachToken({ $0.isLinebreak }) { i, token in
            let start = formatter.startOfLine(atIndex: i)
            if case .whitespace(let string) = formatter.tokens[start] {
                if string.hasPrefix("\t") {
                    increment("\t")
                } else {
                    let length = string.characters.count
                    for i in [8, 4, 3, 2, 1] {
                        if length % i == 0 {
                            increment(String(repeating: " ", count: i))
                            break
                        }
                    }
                }
            }
        }
        return indents.sorted(by: { $0.count > $1.count }).first.map({ $0.indent }) ?? options.indent
    }()

    options.linebreak = {
        var cr: Int = 0, lf: Int = 0, crlf: Int = 0
        formatter.forEachToken { i, token in
            switch token {
            case .linebreak("\n"):
                lf += 1
            case .linebreak("\r"):
                cr += 1
            case .linebreak("\r\n"):
                crlf += 1
            default:
                break
            }
        }
        var max = lf
        var linebreak = "\n"
        if cr > max {
            max = cr
            linebreak = "\r"
        }
        if crlf > max {
            max = crlf
            linebreak = "\r\n"
        }
        return linebreak
    }()

    // No way to infer this
    options.allowInlineSemicolons = true

    options.spaceAroundRangeOperators = {
        var spaced = 0, unspaced = 0
        formatter.forEachToken { i, token in
            if token == .symbol("...") || token == .symbol("..<") {
                if let nextToken = formatter.nextNonWhitespaceOrCommentOrLinebreakToken(fromIndex: i) {
                    if nextToken.string != ")" && nextToken.string != "," {
                        if formatter.tokenAtIndex(i + 1)?.isWhitespaceOrLinebreak == true {
                            spaced += 1
                        } else {
                            unspaced += 1
                        }
                    }
                }
            }
        }
        return spaced >= unspaced
    }()

    options.useVoid = {
        var voids = 0, tuples = 0
        formatter.forEachToken(.identifier("Void")) { i, token in
            if let prevToken = formatter.previousNonWhitespaceOrCommentOrLinebreakToken(fromIndex: i),
                prevToken == .symbol(".") || prevToken == .keyword("typealias") {
                return
            }
            voids += 1
        }
        formatter.forEachToken(.startOfScope("(")) { i, token in
            if let prevIndex = formatter.indexOfPreviousToken(fromIndex: i, matching: { !$0.isWhitespaceOrCommentOrLinebreak }),
                let prevToken = formatter.tokenAtIndex(prevIndex), prevToken.string == "->",
                let nextIndex = formatter.indexOfNextToken(fromIndex: i, matching: { !$0.isWhitespaceOrLinebreak }),
                let nextToken = formatter.tokenAtIndex(nextIndex), nextToken.string == ")",
                formatter.nextNonWhitespaceOrCommentOrLinebreakToken(fromIndex: nextIndex)?.string != "->" {
                tuples += 1
            }
        }
        return voids >= tuples
    }()

    options.trailingCommas = {
        var trailing = 0, noTrailing = 0
        formatter.forEachToken(.endOfScope("]")) { i, token in
            if let linebreakIndex = formatter.indexOfPreviousToken(fromIndex: i, matching: {
                return !$0.isWhitespaceOrComment }), case .linebreak = formatter.tokens[linebreakIndex] {
                if let previousTokenIndex = formatter.indexOfPreviousToken(fromIndex: linebreakIndex + 1, matching: {
                    return !$0.isWhitespaceOrCommentOrLinebreak
                }), let token = formatter.tokenAtIndex(previousTokenIndex) {
                    switch token.string {
                    case "[", ":":
                        break // do nothing
                    case ",":
                        trailing += 1
                    default:
                        noTrailing += 1
                    }
                }
            }
        }
        return trailing >= noTrailing
    }()

    options.indentComments = {
        var shouldIndent = true
        var nestedComments = 0
        var prevIndent: Int?
        var lastToken = Token.whitespace("")
        for token in formatter.tokens {
            switch token {
            case .startOfScope:
                if token.string == "/*" {
                    nestedComments += 1
                }
                prevIndent = nil
            case .endOfScope:
                if token.string == "*/" {
                    if nestedComments > 0 {
                        if case .linebreak = lastToken {
                            if prevIndent != nil && prevIndent! >= 2 {
                                shouldIndent = false
                                break
                            }
                            prevIndent = 0
                        }
                        nestedComments -= 1
                    } else {
                        break // might be fragment, or syntax error
                    }
                }
                prevIndent = nil
            case .whitespace:
                if case .linebreak = lastToken, nestedComments > 0 {
                    let indent = token.string.characters.count
                    if prevIndent != nil && abs(prevIndent! - indent) >= 2 {
                        shouldIndent = false
                        break
                    }
                    prevIndent = indent
                }
            case .commentBody:
                if case .linebreak = lastToken, nestedComments > 0 {
                    if prevIndent != nil && prevIndent! >= 2 {
                        shouldIndent = false
                        break
                    }
                    prevIndent = 0
                }
            default:
                break
            }
            lastToken = token
        }
        return shouldIndent
    }()

    options.truncateBlankLines = {
        var truncated = 0, untruncated = 0
        var scopeStack = [Token]()
        formatter.forEachToken { i, token in
            switch token {
            case .startOfScope:
                scopeStack.append(token)
            case .linebreak:
                if let nextToken = formatter.tokenAtIndex(i + 1) {
                    switch nextToken {
                    case .whitespace:
                        if let nextToken = formatter.tokenAtIndex(i + 2) {
                            if case .linebreak = nextToken {
                                untruncated += 1
                            }
                        } else {
                            untruncated += 1
                        }
                    case .linebreak:
                        truncated += 1
                    default:
                        break
                    }
                }
            default:
                if let scope = scopeStack.last, token.closesScopeForToken(scope) {
                    scopeStack.removeLast()
                }
            }
        }
        return truncated >= untruncated
    }()

    // We can't infer these yet, so default them to false
    options.insertBlankLines = false
    options.removeBlankLines = false

    options.allmanBraces = {
        var allman = 0, knr = 0
        formatter.forEachToken(.startOfScope("{")) { i, token in
            // Check this isn't an inline block
            guard let nextLinebreakIndex = formatter.indexOfNextToken(fromIndex: i, matching: {
                $0.isLinebreak
            }), let closingBraceIndex = formatter.indexOfNextToken(fromIndex: i, matching: {
                return $0 == .endOfScope("}") }), nextLinebreakIndex < closingBraceIndex else { return }
            // Check if brace is wrapped
            if let previousTokenIndex = formatter.indexOfPreviousToken(fromIndex: i, matching: {
                !$0.isWhitespace }), let previousToken = formatter.tokenAtIndex(previousTokenIndex) {
                switch previousToken {
                case .identifier, .endOfScope:
                    knr += 1
                case .linebreak:
                    allman += 1
                default:
                    break
                }
            }
        }
        return allman > knr
    }()

    options.ifdefIndentMode = {
        var indented = 0, noindented = 0, outdented = 0
        formatter.forEachToken(.startOfScope("#if")) { i, token in
            if let indent = formatter.tokenAtIndex(i - 1), case .whitespace(let string) = indent,
                !string.isEmpty {
                // Indented, check next line
                if let nextLineIndex = formatter.indexOfNextToken(fromIndex: i, matching: { $0.isLinebreak }),
                    let nextIndex = formatter.indexOfNextToken(fromIndex: nextLineIndex, matching: {
                        !$0.isWhitespaceOrLinebreak }) {
                    switch formatter.tokens[nextIndex - 1] {
                    case .whitespace(let innerString):
                        if innerString.isEmpty {
                            // Error?
                            return
                        } else if innerString == string {
                            noindented += 1
                        } else {
                            // Assume more indented, as less would be a mistake
                            indented += 1
                        }
                    case .linebreak:
                        // Could be noindent or outdent
                        noindented += 1
                        outdented += 1
                    default:
                        break
                    }
                }
                // Error?
                return
            }
            // Not indented, check next line
            if let nextLineIndex = formatter.indexOfNextToken(fromIndex: i, matching: { $0.isLinebreak }),
                let nextIndex = formatter.indexOfNextToken(fromIndex: nextLineIndex, matching: {
                    !$0.isWhitespaceOrLinebreak }) {
                switch formatter.tokens[nextIndex - 1] {
                case .whitespace(let string):
                    if string.isEmpty {
                        fallthrough
                    } else if string == formatter.options.indent {
                        // Could be indent or outdent
                        indented += 1
                        outdented += 1
                    } else {
                        // Assume more indented, as less would be a mistake
                        outdented += 1
                    }
                case .linebreak:
                    // Could be noindent or outdent
                    noindented += 1
                    outdented += 1
                default:
                    break
                }
            }
            // Error?
        }
        if noindented > indented {
            return outdented > noindented ? .outdent : .noindent
        } else {
            return outdented > indented ? .outdent : .indent
        }
    }()

    options.uppercaseHex = {
        let prefix = "0x"
        var uppercase = 0, lowercase = 0
        formatter.forEachToken { i, token in
            if case .number(let string) = token, string.hasPrefix(prefix) {
                if string == string.lowercased() {
                    lowercase += 1
                } else {
                    let value = string.substring(from: prefix.endIndex)
                    if value == value.uppercased() {
                        uppercase += 1
                    }
                }
            }
        }
        return uppercase > lowercase
    }()

    return options
}
