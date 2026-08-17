import Foundation

// Shared across app (ContentView can use this type)
enum SolverMode: String, CaseIterable, Identifiable {
	case hybrid = "Hybrid"
	case average = "Average"
	case worstCase = "Worst-case"
	var id: String { rawValue }
}

struct WordleSolver {

	static let patternCount = 243

	// Word lists (must match the ordering used to generate patterns.bin)
	let answers: [String]
	let allowed: [String]

	// patterns[guessIndex * answersCount + answerIndex] -> 0...242
	let patternTable: [UInt8]

	// Fast lookup from word -> index
	private let allowedIndexByWord: [String: Int]

	// Candidates stored as indices into `answers`
	private var candidateAnswerIndices: [Int]
	// Fallback candidates are indices into `allowed`.
	private var extendedCandidateIndices: [Int] = []
	private var observations: [(guessIndex: Int, patternCode: UInt8)] = []
	private(set) var isUsingExtendedCandidates = false

	// For UI only (avoid using this in hot loops)
	var candidates: [String] {
		if isUsingExtendedCandidates {
			return extendedCandidateIndices.map { allowed[$0] }
		}
		return candidateAnswerIndices.map { answers[$0] }
	}
	var candidateCount: Int {
		isUsingExtendedCandidates
			? extendedCandidateIndices.count
			: candidateAnswerIndices.count
	}

	init(answers: [String], allowed: [String]) {
		self.answers = answers
		self.allowed = allowed
		self.candidateAnswerIndices = Array(answers.indices)

		// Build word->index map for allowed guesses
		self.allowedIndexByWord = Dictionary(
			uniqueKeysWithValues: allowed.enumerated().map {
				($0.element, $0.offset)
			}
		)

		// Load precomputed patterns.bin from app bundle
		guard
			let url = Bundle.main.url(
				forResource: "patterns",
				withExtension: "bin"
			),
			let data = try? Data(contentsOf: url)
		else {
			fatalError("patterns.bin not found in bundle")
		}

		let expected = answers.count * allowed.count
		guard data.count == expected else {
			fatalError(
				"patterns.bin size mismatch. Expected \(expected) bytes, got \(data.count). Make sure you generated with same answers/allowed ordering."
			)
		}

		self.patternTable = [UInt8](data)
	}

	func isAllowedGuess(_ word: String) -> Bool {
		allowedIndexByWord[word.lowercased()] != nil
	}

	mutating func reset() {
		candidateAnswerIndices = Array(answers.indices)
		extendedCandidateIndices = []
		observations = []
		isUsingExtendedCandidates = false
	}

	mutating func apply(guess: String, patternCode: Int) {
		guard let gi = allowedIndexByWord[guess.lowercased()],
			(0..<Self.patternCount).contains(patternCode)
		else { return }

		let target = UInt8(patternCode)
		observations.append((gi, target))

		if isUsingExtendedCandidates {
			extendedCandidateIndices = extendedCandidateIndices.filter { ai in
				Self.patternCode(guess: allowed[gi], answer: allowed[ai]) == target
			}
			return
		}

		let A = answers.count
		let base = gi * A

		candidateAnswerIndices = candidateAnswerIndices.filter { ai in
			patternTable[base + ai] == target
		}

		if candidateAnswerIndices.isEmpty {
			activateExtendedCandidates()
		}
	}

	private mutating func activateExtendedCandidates() {
		isUsingExtendedCandidates = true
		extendedCandidateIndices = allowed.indices.filter { answerIndex in
			observations.allSatisfy { observation in
				Self.patternCode(
					guess: allowed[observation.guessIndex],
					answer: allowed[answerIndex]
				) == observation.patternCode
			}
		}
	}

	private static func patternCode(guess: String, answer: String) -> UInt8 {
		let guessLetters = Array(guess.utf8)
		let answerLetters = Array(answer.utf8)
		var result = Array(repeating: UInt8(0), count: 5)
		var remainingCounts = Array(repeating: 0, count: 26)

		for i in 0..<5 {
			if guessLetters[i] == answerLetters[i] {
				result[i] = 2
			} else {
				remainingCounts[Int(answerLetters[i] - 97)] += 1
			}
		}

		for i in 0..<5 where result[i] == 0 {
			let letterIndex = Int(guessLetters[i] - 97)
			if remainingCounts[letterIndex] > 0 {
				result[i] = 1
				remainingCounts[letterIndex] -= 1
			}
		}

		var code = 0
		var powerOfThree = 1
		for value in result {
			code += Int(value) * powerOfThree
			powerOfThree *= 3
		}
		return UInt8(code)
	}

	struct Suggestion: Identifiable {
		let id = UUID()
		let word: String
		let entropy: Double
		let expectedRemaining: Double
		let worstBucket: Int
		let isCandidate: Bool
		let waste: Int
	}

	struct KnownInfo {
		let greens: [Character?]  // length 5, nil if unknown
		let present: Set<Character>  // letters known to exist (yellow or green)
		let absent: Set<Character>
	}

	func suggest(
		topK: Int = 10,
		hardMode: Bool = false,
		mode: SolverMode = .hybrid,
		known: KnownInfo? = nil
	) -> [Suggestion] {
		let n = candidateCount
		guard n > 0 else { return [] }

		// If only one candidate, return it directly
		if n == 1, let w = candidates.first {
			return [
				Suggestion(
					word: w,
					entropy: 0,
					expectedRemaining: 1,
					worstBucket: 1,
					isCandidate: true,
					waste: 0
				)
			]
		}

		let A = answers.count
		let dn = Double(n)

		// Guess pool as allowed indices
		let guessIndices: [Int]
		if hardMode {
			// Only allow guesses that are still possible answers (but must map into allowed list)
			guessIndices = candidateAllowedIndices
		} else {
			guessIndices = Array(allowed.indices)
		}

		// For isCandidate marking in UI
		let candidateAllowedSet = Set(candidateAllowedIndices)

		var results: [Suggestion] = []
		results.reserveCapacity(min(topK, guessIndices.count))

		// Main scoring loop (all fast table lookups)
		for gi in guessIndices {
			var counts = Array(repeating: 0, count: Self.patternCount)

			if isUsingExtendedCandidates {
				for ai in extendedCandidateIndices {
					let p = Int(Self.patternCode(guess: allowed[gi], answer: allowed[ai]))
					counts[p] += 1
				}
			} else {
				let base = gi * A
				for ai in candidateAnswerIndices {
					let p = Int(patternTable[base + ai])
					counts[p] += 1
				}
			}

			var entropy = 0.0
			var expRemain = 0.0
			var worst = 0

			for c in counts where c > 0 {
				if c > worst { worst = c }
				let pc = Double(c) / dn
				entropy -= pc * log2(pc)
				expRemain += Double(c * c) / dn
			}

			var waste = 0

			if !hardMode, let info = known {
				let letters = Array(allowed[gi].uppercased())
				let unique = Set(letters)

				// 1) Heavy penalty: using known green letters in their known positions
				for i in 0..<5 {
					if let g = info.greens[i], letters[i] == g { waste += 2 }
				}

				// 2) Light penalty: reusing known-present letters (less exploration)
				for c in unique where info.present.contains(c) {
					waste += 1
				}

				// 3) Heavy penalty: using known-absent letters (bad guesses)
				// Use a higher weight than present letters.
				for c in unique where info.absent.contains(c) {
					waste += 4
				}

				// 4) duplicates penalty (less coverage)
				waste += (5 - unique.count)
			}

			results.append(
				Suggestion(
					word: allowed[gi],
					entropy: entropy,
					expectedRemaining: expRemain,
					worstBucket: worst,
					isCandidate: candidateAllowedSet.contains(gi),
					waste: waste
				)
			)
		}

		// Sorting rules per mode
		results.sort { a, b in
			switch mode {
			case .hybrid:
				// Best of both worlds:
				// minimize expected remaining
				if a.expectedRemaining != b.expectedRemaining {
					return a.expectedRemaining < b.expectedRemaining
				}
				// maximize entropy
				if a.entropy != b.entropy { return a.entropy > b.entropy }
				// minimize minimax (smallest worst bucket)
				if a.worstBucket != b.worstBucket {
					return a.worstBucket < b.worstBucket
				}
				// prefer candidate answers, then alphabetical
				if a.isCandidate != b.isCandidate {
					return a.isCandidate && !b.isCandidate
				}
				if !hardMode, a.waste != b.waste { return a.waste < b.waste }
				return a.word < b.word

			case .average:
				// maximize entropy
				if a.entropy != b.entropy { return a.entropy > b.entropy }
				// then expected remaining
				if a.expectedRemaining != b.expectedRemaining {
					return a.expectedRemaining < b.expectedRemaining
				}
				// then prefer candidate
				if a.isCandidate != b.isCandidate {
					return a.isCandidate && !b.isCandidate
				}
				if !hardMode, a.waste != b.waste { return a.waste < b.waste }
				return a.word < b.word

			case .worstCase:
				// minimize worst bucket
				if a.worstBucket != b.worstBucket {
					return a.worstBucket < b.worstBucket
				}
				// then expected remaining
				if a.expectedRemaining != b.expectedRemaining {
					return a.expectedRemaining < b.expectedRemaining
				}
				// then prefer candidate
				if a.isCandidate != b.isCandidate {
					return a.isCandidate && !b.isCandidate
				}
				if !hardMode, a.waste != b.waste { return a.waste < b.waste }
				return a.word < b.word
			}
		}

		return Array(results.prefix(topK))
	}

	private var candidateAllowedIndices: [Int] {
		if isUsingExtendedCandidates {
			return extendedCandidateIndices
		}
		return candidateAnswerIndices.compactMap { allowedIndexByWord[answers[$0]] }
	}
}

// Convenience
private func log2(_ x: Double) -> Double {
	Foundation.log(x) / Foundation.log(2.0)
}
