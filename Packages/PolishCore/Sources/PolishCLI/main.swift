// polish-cli: run the PolishCore pipeline from the terminal.
//
//   polish-cli golden [--golden PATH] [--out PATH] [--limit N] [--ids ID...] [--temperature T] [--no-keep-style]
//                     [--tone TONE] [--tone-prompt PATH] [--two-stage]
//   (--two-stage: polish in Keep my tone first, then restyle that result in TONE)
//   (--tone-prompt: a prompts/vN.txt restyle template for the non-keep tones, with prompts/vN-tones/;
//    default: what the app ships, v2 for Casual and Professional and v1 for the rest)
//   polish-cli rewrite [--tone keep|casual|professional|concise] [--tone-prompt PATH] [--two-stage] [TEXT]   (reads stdin without TEXT)
//
// `golden` writes one JSON object per row with the same columns as eval/run.py, so eval/compare.py
// can score Swift and Python runs with the same metrics.

import Foundation
import PolishCore

struct Options {
    var command = "help"
    var golden = "golden/golden.jsonl"
    var out: String?
    var limit: Int?
    var ids: [String] = []
    var temperature = 0.2
    var keepStyle = true
    var tone = Tone.keep
    var tonePrompt: String?
    var twoStage = false
    var text: [String] = []
}

func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var rest = arguments[...]
    if let first = rest.first {
        options.command = first
        rest = rest.dropFirst()
    }
    func value(_ name: String) -> String {
        guard let next = rest.popFirst() else { fail("\(name) needs a value") }
        return next
    }
    while let argument = rest.popFirst() {
        switch argument {
        case "--golden": options.golden = value(argument)
        case "--out": options.out = value(argument)
        case "--limit":
            guard let limit = Int(value(argument)) else { fail("--limit needs a number") }
            options.limit = limit
        case "--temperature":
            guard let temperature = Double(value(argument)) else { fail("--temperature needs a number") }
            options.temperature = temperature
        case "--no-keep-style": options.keepStyle = false
        case "--tone":
            guard let tone = Tone(rawValue: value(argument)) else { fail("unknown tone") }
            options.tone = tone
        case "--tone-prompt": options.tonePrompt = value(argument)
        case "--two-stage": options.twoStage = true
        case "--ids":
            while let id = rest.first, !id.hasPrefix("--") {
                options.ids.append(id)
                rest = rest.dropFirst()
            }
        default: options.text.append(argument)
        }
    }
    return options
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("polish-cli: \(message)\n".utf8))
    exit(2)
}

struct GoldenRow: Codable {
    var id: String
    var input: String
    var expected: String
    var tags: [String]
}

/// One result row; keys match the DataFrame columns of eval/run.py.
struct Record: Encodable {
    var id: String
    var input: String
    var expected: String
    var tags: [String]
    var variant: String
    var tone: String
    var schema = "mistakes"
    var guardrails = "default"
    var keep_style: Bool
    var temperature: Double
    var tokens: Int
    var attempts: Int
    var error: String?
    var raw: String?
    var problems: [String]
    var final_problems: [String]
    var output: String
    var fallback: Bool
    var latency_s: Double
    var mistakes: [String]
    var chunks: Int
}

func runGolden(_ options: Options) async throws {
    let lines = try String(contentsOfFile: options.golden, encoding: .utf8).split(separator: "\n")
    var rows = try lines.map { try JSONDecoder().decode(GoldenRow.self, from: Data($0.utf8)) }
    if !options.ids.isEmpty {
        rows = rows.filter { options.ids.contains($0.id) }
    }
    if let limit = options.limit {
        rows = Array(rows.prefix(limit))
    }

    var configuration = Pipeline.Configuration()
    configuration.temperature = options.temperature
    configuration.keepWriterStyle = options.keepStyle
    let instructions = try makeInstructions(options)
    let variant = options.tone == .keep ? "v1"
        : options.tonePrompt.map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
            ?? (Prompt.v2.tones[options.tone] == nil ? "v1" : "v2")
    let pipeline = Pipeline(instructions: instructions, configuration: configuration)
    if case .unavailable = ModelStatus.current() {
        fail("model not available: \(ModelStatus.current().menuTitle)")
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let stamp = formatter.string(from: .now)
    let out = options.out ?? "eval/runs/\(stamp)-swift-\(variant)-\(options.tone.rawValue)-t\(options.temperature).jsonl"
    try FileManager.default.createDirectory(
        at: URL(filePath: out).deletingLastPathComponent(), withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var output = Data()

    for (index, row) in rows.enumerated() {
        let tokens = (try? Protector().protect(row.input).tokens.count) ?? 0
        var record = Record(
            id: row.id, input: row.input, expected: row.expected, tags: row.tags,
            variant: variant, tone: options.tone.rawValue, keep_style: options.keepStyle, temperature: options.temperature, tokens: tokens, attempts: 0,
            problems: [], final_problems: [], output: row.input, fallback: true, latency_s: 0, mistakes: [], chunks: 0
        )
        let start = ContinuousClock.now
        do {
            let result = try await polish(row.input, with: pipeline, options)
            let attempts = result.trace.chunks.flatMap(\.attempts)
            record.attempts = attempts.count
            record.raw = result.trace.chunks.compactMap { $0.attempts.first?.raw }.joined(separator: "\n\n")
            record.problems = result.trace.chunks.flatMap { $0.attempts.first?.failures ?? [] }.map(\.description)
            record.final_problems = result.trace.chunks.flatMap { $0.attempts.last?.failures ?? [] }.map(\.description)
            record.mistakes = result.trace.chunks.flatMap { $0.attempts.first?.mistakes ?? [] }
            record.chunks = result.trace.chunks.count
            record.output = result.text
            record.fallback = result.didFallBack
        } catch let error as PolishError {
            record.error = error.code
        }
        let elapsed = ContinuousClock.now - start
        record.latency_s = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        output.append(try encoder.encode(record))
        output.append(0x0A)
        FileHandle.standardError.write(Data("\r\(index + 1)/\(rows.count)".utf8))
    }
    try output.write(to: URL(filePath: out))
    FileHandle.standardError.write(Data("\nSaved \(out)\n".utf8))
}

/// One draft in the chosen tone; with `--two-stage`, the Keep my tone result is restyled instead of the draft.
func polish(_ text: String, with pipeline: Pipeline, _ options: Options) async throws -> PolishResult {
    guard options.twoStage, options.tone != .keep else {
        return try await pipeline.polish(text: text, tone: options.tone)
    }
    let corrected = try await pipeline.polish(text: text, tone: .keep)
    return try await pipeline.polish(text: corrected.text, tone: options.tone)
}

/// The shipped prompts, or a restyle prompt from disk for the non-keep tones.
func makeInstructions(_ options: Options) throws -> InstructionsBuilder {
    guard let tonePrompt = options.tonePrompt else { return InstructionsBuilder() }
    return InstructionsBuilder(restyle: try .init(contentsOf: URL(filePath: tonePrompt)))
}

func runRewrite(_ options: Options) async throws {
    let instructions = try makeInstructions(options)
    let text = options.text.isEmpty
        ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        : options.text.joined(separator: " ")
    do {
        let result = try await polish(text, with: Pipeline(instructions: instructions), options)
        print(result.text)
        if result.didFallBack {
            let reasons = result.fallbacks.flatMap { $0 }.map(\.description).joined(separator: ", ")
            FileHandle.standardError.write(Data("(kept the original: \(reasons))\n".utf8))
        }
    } catch let error as PolishError {
        fail(error.message)
    }
}

let options = parse(Array(CommandLine.arguments.dropFirst()))
switch options.command {
case "golden": try await runGolden(options)
case "rewrite": try await runRewrite(options)
default:
    print("""
        usage: polish-cli golden [--golden PATH] [--out PATH] [--limit N] [--ids ID...] [--temperature T] [--no-keep-style]
                                 [--tone keep|casual|professional|concise] [--tone-prompt PATH] [--two-stage]
               polish-cli rewrite [--tone keep|casual|professional|concise] [--tone-prompt PATH] [--two-stage] [TEXT]
        """)
}
