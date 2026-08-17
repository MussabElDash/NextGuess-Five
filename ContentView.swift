import SwiftUI
import UIKit

struct GuessRow: Identifiable {
	let id = UUID()
	var word: String = ""
	var colors: [Int] = [0, 0, 0, 0, 0]  // 0 gray, 1 yellow, 2 green
}

struct GuessHistoryRowView: View {
	let row: GuessRow

	var body: some View {
		HStack(spacing: 8) {
			ForEach(0..<5, id: \.self) { i in
				let letter = letterAt(i, in: row.word)
				Tile(letter: letter, state: row.colors[i])
			}
			Spacer()
			Text(row.word.uppercased())
				.font(.system(.caption, design: .monospaced))
				.foregroundStyle(.secondary)
		}
		.padding(.vertical, 4)
	}

	private func letterAt(_ i: Int, in word: String) -> String {
		guard word.count == 5 else { return "" }
		let idx = word.index(word.startIndex, offsetBy: i)
		return String(word[idx]).uppercased()
	}
}

struct ContentView: View {
	@State private var solver: WordleSolver = {
		let answers = loadWords(named: "answers_clean")
		let allowed = loadWords(named: "allowed_combined_sorted")
		return WordleSolver(answers: answers, allowed: allowed)
	}()

	@State private var rows: [GuessRow] = [GuessRow()]
	@State private var hardMode: Bool = false
	@State private var suggestions: [WordleSolver.Suggestion] = []
	@State private var mode: SolverMode = .hybrid
	@State private var openers: [String] = loadWords(named: "openers")
	@State private var showAbout = false

	private let tileSize: CGFloat = 48
	private let tileSpacing: CGFloat = 8

	private var currentGuess: String {
		rows[rows.count - 1].word
	}
	
	private var isShowingPrecomputedOpeners: Bool {
		solver.candidateCount == solver.answers.count &&
		rows.count == 1 &&
		(rows.first?.word.isEmpty ?? true)
	}
	
	private var canAddGuess: Bool {
		!hasNoCandidates &&
		currentGuess.count == 5 &&
		solver.isAllowedGuess(currentGuess)
	}
	
	private var hasNoCandidates: Bool {
		solver.candidateCount == 0
	}

	private var candidateLabel: String {
		solver.isUsingExtendedCandidates ? "Extended candidates" : "Candidates"
	}

	private var fieldState: GuessTextFieldTile.FieldState {
		if currentGuess.count < 5 { return .typing }
		return canAddGuess ? .valid : .invalid
	}

	var body: some View {
		NavigationStack {
			GeometryReader { geo in
				let isWide = geo.size.width >= 820  // iPad landscape will be wide; iPhone won't

				Group {
					if isWide {
						wideLayout
					} else {
						narrowLayout
					}
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			//			.navigationTitle("NextGuess Five")
			.sheet(isPresented: $showAbout) {
				AboutView()
			}
			.onAppear {
				recomputeSuggestions()
			}
		}
	}

	// MARK: - Layouts

	private var narrowLayout: some View {
		VStack(spacing: 12) {
			if solver.candidateCount == solver.answers.count {
				Text("Best openers (precomputed)")
					.font(.caption)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .center)
			}
			Text("\(candidateLabel): \(solver.candidateCount)")
				.font(.headline)
				.frame(maxWidth: .infinity, alignment: .center)

			if solver.isUsingExtendedCandidates && !hasNoCandidates {
				extendedSearchNotice
			}

			inputArea
				.frame(maxWidth: .infinity, alignment: .center)

			actionButtons
				.frame(maxWidth: .infinity, alignment: .center)

			List {
				let history = Array(rows.dropLast()).filter {
					$0.word.count == 5
				}
				if !history.isEmpty {
					Section("History") {
						ForEach(history) { r in
							GuessHistoryRowView(row: r)
						}
					}
				}

				Section("Top Suggestions") {
					if hasNoCandidates {
						VStack(spacing: 8) {
							Image(systemName: "exclamationmark.triangle")
								.font(.title2)
								.foregroundStyle(.orange)

							Text("No possible answers remain")
								.font(.headline)

							Text("The entered feedback is inconsistent with the available answer list. Check the tile colors or undo the last guess.")
								.font(.caption)
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.center)
						}
						.frame(maxWidth: .infinity)
						.padding(.vertical, 20)
						.listRowSeparator(.hidden)
					} else {
						suggestionsRows
					}
				}

				mainControls
			}
			.listStyle(.insetGrouped)
		}
	}

	private var wideLayout: some View {
		HStack(spacing: 0) {

			// LEFT column: controls + input + buttons + history
			VStack(spacing: 16) {
				mainControls

				if solver.candidateCount == solver.answers.count {
					Text("Best openers (precomputed)")
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				Text("\(candidateLabel): \(solver.candidateCount)")
					.font(.headline)

				if solver.isUsingExtendedCandidates && !hasNoCandidates {
					extendedSearchNotice
				}

				inputArea
				actionButtons

				// History gets its own list on iPad/wide
				List {
					let history = Array(rows.dropLast()).filter {
						$0.word.count == 5
					}
					if !history.isEmpty {
						Section("History") {
							ForEach(history) { r in
								GuessHistoryRowView(row: r)
									.listRowInsets(
										EdgeInsets(
											top: 6,
											leading: 12,
											bottom: 6,
											trailing: 12
										)
									)
							}
						}
					} else {
						Section("History") {
							Text("No guesses yet")
								.foregroundStyle(.secondary)
								.frame(maxWidth: .infinity, alignment: .leading)
								.listRowInsets(
									EdgeInsets(
										top: 8,
										leading: 12,
										bottom: 8,
										trailing: 12
									)
								)
						}
					}
				}
			}
			.frame(minWidth: 360, maxWidth: 420)  // left rail width

			// RIGHT column: suggestions list
			List {
				Section("Top Suggestions") {
					if hasNoCandidates {
						VStack(spacing: 8) {
							Image(systemName: "exclamationmark.triangle")
								.font(.title2)
								.foregroundStyle(.orange)

							Text("No possible answers remain")
								.font(.headline)

							Text("The entered feedback is inconsistent with the available answer list. Check the tile colors or undo the last guess.")
								.font(.caption)
								.foregroundStyle(.secondary)
								.multilineTextAlignment(.center)
						}
						.frame(maxWidth: .infinity)
						.padding(.vertical, 20)
						.listRowSeparator(.hidden)
					} else {
						suggestionsRows
					}
				}
			}
			.headerProminence(.increased)  // or remove; preference
			.layoutPriority(1)
			.frame(maxWidth: .infinity)
		}
	}

	private var mainControls: some View {
		VStack(spacing: 12) {

			HStack {
				Toggle("Hard mode", isOn: $hardMode)
				Spacer()
			}
			.padding(.horizontal)

			HStack(spacing: 10) {
				Picker("Mode", selection: $mode) {
					ForEach(SolverMode.allCases) { m in
						Text(m.rawValue).tag(m)
					}
				}
				.pickerStyle(.segmented)

				Button {
					showAbout = true
				} label: {
					Image(systemName: "questionmark.circle")
						.imageScale(.large)
						.padding(6)
				}
				.buttonStyle(.plain)
				.accessibilityLabel("About NextGuess Five")
			}
			.padding(.horizontal)
			.onChange(of: mode) { _, _ in recomputeSuggestions() }
			.onChange(of: hardMode) { _, _ in recomputeSuggestions() }
		}
	}

	private var inputArea: some View {
		VStack(spacing: 8) {
			GuessTextFieldTile(
				placeholder: "Enter Guess",
				text: bindingForCurrentWord(),
				state: fieldState,
				tileSize: tileSize,
				tileSpacing: tileSpacing
			)

			if currentGuess.count == 5 && !solver.isAllowedGuess(currentGuess) {
				Text("Word Not Allowed")
					.font(.caption)
					.foregroundStyle(.red)
			}

			HStack(spacing: 8) {
				ForEach(0..<5, id: \.self) { i in
					let v = currentColors()[i]
					Tile(letter: currentLetter(i), state: v)
						.onTapGesture { cycleColor(i) }
				}
			}
		}
	}

	private var actionButtons: some View {
		HStack {
			Button("Add Guess") { addGuess() }
				.buttonStyle(.borderedProminent)
				.disabled(!canAddGuess)

			Button("Undo") { undo() }
				.buttonStyle(.bordered)
				.disabled(!canUndo)

			Button("Reset") { reset() }
				.buttonStyle(.bordered)
		}
	}

	private var extendedSearchNotice: some View {
		Label(
			"No matches in the primary answer set. Searching the extended word list.",
			systemImage: "magnifyingglass"
		)
		.font(.caption)
		.foregroundStyle(.secondary)
		.multilineTextAlignment(.center)
		.padding(.horizontal)
	}

	@ViewBuilder
	private var suggestionsRows: some View {
		ForEach(suggestions) { s in
			HStack {
				Text(s.word.uppercased())
					.font(.system(.body, design: .monospaced))
					.frame(width: 90, alignment: .leading)

				Spacer()

				if !isShowingPrecomputedOpeners {
					Text(String(format: "H: %.2f", s.entropy))
						.font(.caption)

					Text("W: \(s.worstBucket)")
						.font(.caption)

					Text(String(format: "E: %.1f", s.expectedRemaining))
						.font(.caption)

					if s.isCandidate {
						Text("✓")
							.font(.caption)
					}
				} else {
					Text("Precomputed opener")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			.contentShape(Rectangle())
			.listRowInsets(
				EdgeInsets(
					top: 10,
					leading: 14,
					bottom: 10,
					trailing: 14
				)
			)
			.onTapGesture {
				rows[rows.count - 1].word = s.word.uppercased()
				rows[rows.count - 1].colors = [0, 0, 0, 0, 0]

				UIPasteboard.general.string = s.word.uppercased()

				let generator = UIImpactFeedbackGenerator(style: .light)
				generator.impactOccurred()
			}
		}
	}

	// MARK: - About Modal

	struct AboutView: View {
		@Environment(\.dismiss) private var dismiss

		var body: some View {
			NavigationStack {
				ScrollView {
					VStack(alignment: .leading, spacing: 14) {

						Text("About NextGuess Five")
							.font(.title2).bold()

						Text(
							"NextGuess Five helps solve five-letter word puzzles by ranking guesses using information theory and worst-case analysis. After each guess, enter the puzzle’s color feedback and the app will narrow the possible answers and recommend the strongest next guesses."
						)
						.font(.body)

						Divider()

						Text("How to use it")
							.font(.headline)

						VStack(alignment: .leading, spacing: 8) {
							Text(
								"1) Type a 5-letter guess (only valid allowed words enable Add Guess)."
							)
							Text("2) Tap each tile to match the puzzle feedback:")
							Text("   • Gray = letter not in the word")
							Text(
								"   • Yellow = letter in the word, wrong position"
							)
							Text("   • Green = letter correct position")
							Text(
								"3) Tap Add Guess to apply feedback and update suggestions."
							)
							Text(
								"Undo removes the last submitted guess. Reset starts a new puzzle."
							)
						}
						.font(.body)

						Divider()

						Text("Suggestion stats")
							.font(.headline)

						VStack(alignment: .leading, spacing: 8) {
							Text(
								"H: Entropy — Higher is better. Measures expected information gained (how well the guess splits remaining candidates)."
							)
							Text(
								"E: Expected Remaining — Lower is better. Average number of candidates left after this guess."
							)
							Text(
								"W: Worst Bucket — Lower is better. Worst-case remaining candidates (minimax)."
							)
							Text(
								"✓ Candidate — This guess is still a possible answer (not just a legal guess)."
							)
						}
						.font(.body)

						Divider()

						Text("Modes")
							.font(.headline)

						VStack(alignment: .leading, spacing: 8) {
							Text(
								"Hybrid (Default): minimize E, tie-break by W, then prefer ✓ candidates."
							)
							Text(
								"Average (Entropy): maximize H (fast average progress)."
							)
							Text(
								"Worst-case (Minimax): minimize W (most consistent)."
							)
						}
						.font(.body)

						Divider()

						Text("Hard mode")
							.font(.headline)

						Text(
							"When enabled, suggestions are restricted to guesses that satisfy all currently known letter and position constraints."
						)
						.font(.body)
					}
					.padding()
				}
				.navigationTitle("NextGuess Five")
				.toolbar {
					ToolbarItem(placement: .topBarTrailing) {
						Button("Done") { dismiss() }
					}
				}
			}
		}
	}

	// MARK: - UI Helpers

	private func bindingForCurrentWord() -> Binding<String> {
		Binding(
			get: { rows[rows.count - 1].word },
			set: { newValue in
				let cleaned = String(
					newValue.uppercased()
						.filter { $0 >= "A" && $0 <= "Z" }
						.prefix(5)
				)
				rows[rows.count - 1].word = cleaned
			}
		)
	}
	
	private var canUndo: Bool {
		rows.count > 1
	}

	private func currentColors() -> [Int] {
		rows[rows.count - 1].colors
	}

	private func currentLetter(_ i: Int) -> String {
		let w = rows[rows.count - 1].word
		guard i < w.count else { return "" }
		let idx = w.index(w.startIndex, offsetBy: i)
		return String(w[idx]).uppercased()
	}

	private func cycleColor(_ i: Int) {
		rows[rows.count - 1].colors[i] =
			(rows[rows.count - 1].colors[i] + 1) % 3
	}

	// MARK: - Actions

	private func addGuess() {
		guard canAddGuess else { return }

		let row = rows[rows.count - 1]
		let guessLower = row.word.lowercased()

		// Encode pattern
		var code = 0
		var pow3 = 1
		for i in 0..<5 {
			code += row.colors[i] * pow3
			pow3 *= 3
		}

		// Apply to solver
		solver.apply(guess: guessLower, patternCode: code)

		// Add next row
		rows.append(GuessRow())
		recomputeSuggestions()
	}

	private func undo() {
		guard canUndo else { return }

		// 1) Remove the current input row
		rows.removeLast()

		// 2) Remove the last completed guess (the one we want to undo)
		_ = rows.popLast()

		// 3) Remaining rows are the completed history we want to keep
		let remainingCompleted = rows

		// 4) Rebuild solver from scratch using remaining history
		solver.reset()
		for r in remainingCompleted {
			guard r.word.count == 5 else { continue }

			var code = 0
			var pow3 = 1
			for i in 0..<5 {
				code += r.colors[i] * pow3
				pow3 *= 3
			}

			solver.apply(guess: r.word.lowercased(), patternCode: code)
		}

		// 5) Restore UI rows: history + fresh empty input row
		rows = remainingCompleted + [GuessRow()]

		recomputeSuggestions()
	}

	private func reset() {
		rows = [GuessRow()]
		solver.reset()
		recomputeSuggestions()
	}

	private func computeKnownInfo() -> WordleSolver.KnownInfo {
		var greens: [Character?] = Array(repeating: nil, count: 5)
		var present = Set<Character>()
		var absent = Set<Character>()

		// First pass: establish greens + present (yellow/green)
		for r in rows.dropLast() {
			let w = r.word.uppercased()
			guard w.count == 5 else { continue }
			let letters = Array(w)

			for i in 0..<5 {
				if r.colors[i] == 2 {
					greens[i] = letters[i]
					present.insert(letters[i])
				} else if r.colors[i] == 1 {
					present.insert(letters[i])
				}
			}
		}

		// Second pass: mark absent letters safely (handles duplicates)
		for r in rows.dropLast() {
			let w = r.word.uppercased()
			guard w.count == 5 else { continue }
			let letters = Array(w)

			var totalCount: [Character: Int] = [:]
			var nonGrayCount: [Character: Int] = [:]

			for i in 0..<5 {
				let ch = letters[i]
				totalCount[ch, default: 0] += 1
				if r.colors[i] != 0 {
					nonGrayCount[ch, default: 0] += 1
				}
			}

			for (ch, _) in totalCount {
				let ng = nonGrayCount[ch, default: 0]
				if ng == 0 && !present.contains(ch) {
					absent.insert(ch)
				}
			}
		}

		absent.subtract(present)

		return WordleSolver.KnownInfo(
			greens: greens,
			present: present,
			absent: absent
		)
	}

	private func recomputeSuggestions() {
		// No primary or extended candidates match the feedback.
		if solver.candidateCount == 0 {
			suggestions = []
			return
		}

		// No feedback entered yet: show precomputed openers instantly.
		if solver.candidateCount == solver.answers.count &&
			rows.count == 1 &&
			(rows.first?.word.isEmpty ?? true) {

			suggestions = openers.prefix(10).map {
				WordleSolver.Suggestion(
					word: $0,
					entropy: 0,
					expectedRemaining: 0,
					worstBucket: 0,
					isCandidate: true,
					waste: 0
				)
			}
			return
		}

		let known = computeKnownInfo()

		suggestions = solver.suggest(
			topK: 10,
			hardMode: hardMode,
			mode: mode,
			known: known
		)
	}
}

struct Tile: View {
	let letter: String
	let state: Int

	var body: some View {
		Text(letter)
			.font(.system(size: 22, weight: .bold, design: .monospaced))
			.frame(width: 48, height: 48)
			.background(backgroundColor())
			.cornerRadius(8)
			.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary))
	}

	private func backgroundColor() -> Color {
		switch state {
		case 2: return Color.green.opacity(0.75)
		case 1: return Color.yellow.opacity(0.75)
		default: return Color.gray.opacity(0.25)
		}
	}
}

struct GuessTextFieldTile: View {
	enum FieldState {
		case typing
		case valid
		case invalid
	}

	let placeholder: String
	@Binding var text: String
	let state: FieldState
	let tileSize: CGFloat
	let tileSpacing: CGFloat

	private var width: CGFloat { tileSize * 5 + tileSpacing * 4 }

	var body: some View {
		TextField(placeholder, text: $text)
			.textInputAutocapitalization(.characters)
			.autocorrectionDisabled(true)
			.keyboardType(.asciiCapable)
			.multilineTextAlignment(.center)
			.font(.system(size: 22, weight: .bold, design: .monospaced))
			.frame(width: width, height: tileSize)
			.background(backgroundColor)
			.cornerRadius(8)
			.overlay(
				RoundedRectangle(cornerRadius: 8)
					.strokeBorder(borderColor, lineWidth: 2)
			)
			.textContentType(.oneTimeCode)
			.disableAutocorrection(true)
			.onChange(of: text) { _, _ in
				let cleaned = String(
					text.uppercased().filter { $0 >= "A" && $0 <= "Z" }.prefix(
						5
					)
				)
				if text != cleaned { text = cleaned }
			}
	}

	private var borderColor: Color {
		switch state {
		case .typing: return Color.secondary.opacity(0.6)
		case .valid: return Color.green.opacity(0.85)
		case .invalid: return Color.red.opacity(0.85)
		}
	}

	private var backgroundColor: Color {
		switch state {
		case .typing: return Color.gray.opacity(0.12)
		case .valid: return Color.green.opacity(0.12)
		case .invalid: return Color.red.opacity(0.10)
		}
	}
}

// MARK: - Bundle word loading

func loadWords(named: String) -> [String] {
	guard let url = Bundle.main.url(forResource: named, withExtension: "txt"),
		let data = try? Data(contentsOf: url),
		let text = String(data: data, encoding: .utf8)
	else {
		return []
	}
	return
		text
		.split(whereSeparator: \.isNewline)
		.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
		.filter { $0.count == 5 && $0.allSatisfy { $0 >= "a" && $0 <= "z" } }
}
