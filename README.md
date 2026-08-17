# NextGuess Five (iOS) 🟩🟨⬛️

NextGuess Five is a fast, data-driven companion for five-letter word puzzles. It **narrows the solution space instantly** and recommends the **next best guess** using information theory and worst-case analysis. Built with **SwiftUI** and optimized with **offline precomputation** for near-instant suggestions even with large word lists.

---

## ✨ What the app provides

- **Best-next-guess recommendations** based on proven strategy metrics (entropy / expected remaining / minimax).
- **Instant candidate narrowing** after each round of feedback (gray/yellow/green).
- **Extended fallback search** across all allowed words if the primary answer list reaches zero.
- **Multiple solving modes** to match different play styles:
  - **Hybrid (default)**: balanced and strong overall
  - **Average (Entropy)**: fastest average progress
  - **Worst-case (Minimax)**: most consistent / safest
- **Hard Mode toggle** to restrict suggestions to guesses that satisfy known constraints.
- **History + Undo + Reset** to manage a full solving session.
- **Tap-to-fill and copy** a suggested guess for quick use.

---

## 🧠 Solver modes

### 1) Hybrid (Default) — “best of both worlds”
Optimizes for a strong average solve while avoiding bad worst-case outcomes:

1. **Minimize Expected Remaining (E)**  
2. Tie-break by **Worst Bucket (W)** (minimax)  
3. Prefer **candidate answers** (✓), then alphabetical  
4. (Optional heuristic) lower “waste” for non-hard-mode exploration

### 2) Average (Entropy)
Chooses guesses that maximize information gain on average by **maximizing entropy (H)**.

### 3) Worst-case (Minimax)
Chooses guesses that minimize the worst possible remaining search space by **minimizing W**.

---

## 📊 What the suggestion stats mean

Each suggestion includes:

- **H: Entropy** → **higher is better**  
  Measures expected information gained. A guess with high entropy splits the remaining candidates more evenly.

- **E: Expected Remaining** → **lower is better**  
  Expected number of candidates remaining after applying the feedback from this guess.

- **W: Worst Bucket** → **lower is better**  
  Worst-case number of candidates remaining (the largest feedback bucket for this guess).

- **✓ Candidate**  
  The guess is still a possible answer (not just a legal guess).

---

## ⚡ Performance approach

To keep the UI responsive and make recommendations fast, the app uses **precomputed feedback patterns**:

### Precomputed pattern table
A bundled binary file:

- `patterns.bin`
- Stores `pattern(guess, answer)` as a single byte (`UInt8`, values `0...242`)
- Lookup formula:
  - `patternTable[guessIndex * answersCount + answerIndex]`

This avoids recomputing five-letter word puzzle feedback rules inside the hot loop.

### Why not precompute “best guess for every state”?
Because the number of possible candidate sets is astronomical (`2^N`).  
Instead, we precompute the reusable primitive (guess→answer feedback), which makes runtime scoring extremely fast.

---

## 📁 Data files (bundled)

These files are expected in the app bundle:

- `answers_clean.txt`  
  One 5-letter answer per line.

- `allowed_combined_sorted.txt`  
  All legal guesses (answers included), sorted and deduplicated.

- `patterns.bin`  
  The precomputed pattern table built using **exactly** the same ordering as the two files above.

- `openers.txt` *(optional but recommended)*  
  Pre-ranked “best opener” guesses for instant first-screen suggestions.

> ⚠️ IMPORTANT: `patterns.bin` is only valid if `answers_clean.txt` and `allowed_combined_sorted.txt` match the **same ordering** used when generating it.

The solver normally ranks against the curated primary answer set. If no primary
answer matches all entered feedback, it automatically filters the full allowed
list and clearly labels the results as extended candidates. Feedback patterns
for this uncommon fallback path are calculated on device, so the bundled
precomputed table does not need to grow.

---

## 🛠️ Offline generation (recommended)

### Generate clean wordlists + patterns.bin
Use a script to produce:
- `answers_clean.txt`
- `allowed_combined_sorted.txt`
- `patterns.bin`

Example workflow:
1. Start from `answers.txt` + `allowed.txt`
2. Generate the canonical clean files and the binary table once
3. Bundle the outputs in Xcode

### Generate openers.txt
Precompute the top openers (Hybrid by default) to show suggestions instantly before the first guess is entered.

> You can generate separate opener lists per mode if desired:
- `openers_hybrid.txt`
- `openers_average.txt`
- `openers_worstcase.txt`

---

## 🚀 Build & Run

### Requirements
- Xcode (latest recommended)
- iOS device or simulator

### Steps
1. Open the project in Xcode
2. Ensure bundle resources include:
   - `answers_clean.txt`
   - `allowed_combined_sorted.txt`
   - `patterns.bin`
   - `openers.txt` (optional)
3. Select a run destination and hit **Run**

---

## ✅ UX details

### Input validation
- Guess input is constrained to:
  - **A–Z only**
  - **max 5 characters**
- **Add Guess** is disabled unless:
  - the guess is exactly 5 letters
  - it exists in the allowed guess list

### Suggestions interaction
- Tap a suggestion to:
  - autofill the guess input
  - copy the guess to clipboard
  - provide haptic confirmation

---

## 🧩 Project structure (high level)

- `ContentView.swift`
  - UI layout (iPhone/iPad adaptive)
  - history tracking and user interactions
  - computing known constraints from past guesses
  - displaying suggestions and stats

- `WordleSolver.swift`
  - candidate filtering from feedback
  - scoring guesses using precomputed `patterns.bin`
  - strategy modes and sorting rules

---

## 🧪 Notes on correctness (duplicate letters)
The underlying pattern encoding applies standard gray/yellow/green puzzle logic:
- Greens are matched first
- Remaining letters are counted for yellows
- Encoded as base-3 digits across 5 positions (0..242)

---

## 🗺️ Roadmap (optional ideas)
- Mode-specific opener lists (Hybrid/Average/Worst-case)
- Persist game sessions & history across launches
- Candidate list screen with search/filter
- Optional constraint-based hard-mode enforcement
- Extra analytics (solve distribution, average guesses, etc.)

---

## ⚖️ License / Word list note
If you distribute the app publicly, ensure the bundled word lists and all third-party materials comply with their applicable licenses and trademarks.

---

## 🙌 Credits
Built with SwiftUI + offline precomputation for fast, high-quality recommendations.
