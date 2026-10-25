import Testing
@testable import PolishCore

struct ChangesTests {
    func changes(_ original: String, _ rewritten: String) -> [Change] {
        Differ.changes(Differ.diff(original: original, rewritten: rewritten))
    }

    @Test(arguments: [
        ("teh", "the", Change.Reason.spelling),
        ("paragrah", "paragraph", .spelling),
        ("recieve", "receive", .spelling),
        ("their", "there", .wrongWord),
        ("your", "you're", .wrongWord),
        ("then", "than", .wrongWord),
        ("to", "too", .wrongWord),
        ("its", "it's", .punctuation),
        ("dont", "don't", .punctuation),
        ("tomorrow", "tomorrow.", .punctuation),
        ("monday", "Monday", .capitalization),
        ("hey", "Hey,", .capitalization),
        ("look", "looks", .grammar),
        ("return", "returned", .grammar),
        ("is", "are", .grammar),
        ("a", "an", .grammar),
        ("run", "ran", .grammar),
        ("doesnt", "don't", .grammar),
        ("able", "unable", .wording),
        ("tmrw", "tomorrow", .shorthand),
        ("u", "you", .shorthand),
        ("pls", "Please", .shorthand),
        ("in to", "into", .spelling),
        ("#platform-eng ,", "#platform-eng,", .punctuation),
        ("angry", "upset", .wording),
    ])
    func reasonComesFromTheEdit(from: String, to: String, reason: Change.Reason) {
        #expect(changes(from, to) == [Change(from: from, to: to, reason: reason)])
    }

    @Test func oneChangePerRunOfChangedWords() {
        #expect(changes("i think their is a typo in teh doc", "I think there is a typo in the doc.") == [
            Change(from: "i", to: "I", reason: .capitalization),
            Change(from: "their", to: "there", reason: .wrongWord),
            Change(from: "teh", to: "the", reason: .spelling),
            Change(from: "doc", to: "doc.", reason: .punctuation),
        ])
    }

    @Test func addedAndRemovedWordsShowOneSide() {
        #expect(changes("send the report", "please send the report") == [Change(from: "", to: "please", reason: .wording)])
        #expect(changes("the very final report", "the final report") == [Change(from: "very", to: "", reason: .wording)])
    }

    @Test func eachChangedWordKeepsItsOwnReason() {
        #expect(changes("can u send it", "could you please send it") == [
            Change(from: "can", to: "could", reason: .wording),
            Change(from: "u", to: "you please", reason: .shorthand),
        ])
        #expect(changes("their is a issue", "There is an issue.") == [
            Change(from: "their", to: "There", reason: .wrongWord),
            Change(from: "a", to: "an", reason: .grammar),
            Change(from: "issue", to: "issue.", reason: .punctuation),
        ])
    }

    @Test func spacingAloneIsNotAChange() {
        #expect(changes("one  two\nthree", "one two\n\nthree").isEmpty)
        #expect(changes("all good", "all good").isEmpty)
    }
}
