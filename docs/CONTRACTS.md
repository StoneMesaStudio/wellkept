# Wellkept shell — the contract every file compiles against

Written 2026-08-26, before the first Swift file, so that work written in parallel fits together.
Nothing here is a suggestion. If a file needs something not listed, it adds it to its OWN
namespace and does not invent a name in someone else's.

## Ownership — a file has exactly one author

| Area | Files | Owner |
|---|---|---|
| Design primitives | `App/Support/Palette.swift`, `ColorMath.swift`, `Space.swift`, `AppFont.swift`, `Controls.swift`, `Scrolling.swift` | A |
| Shell, sidebar, Overview, the seven faces, demo data | `App/WellkeptApp.swift`, `App/Shell/*`, `App/Sections/*` | B |
| Welcome + setup flow, permission probing | `App/Onboarding/*`, `App/Permissions.swift` | C |
| Settings, Help, Uninstall | `App/Settings/*`, `App/Help/*`, `App/Uninstaller.swift` | D |
| Scripts and tests | `bin/*`, `Tests/*`, `Core/Tests/*` | E |
| Shared vocabulary | `Core/Sources/WellkeptCore/*` | written below, by A |

## Stored preferences — the exact keys

Raw values are permanent and are NEVER the user-visible label. Renaming a section or a mode
must be one line in a `label` property, never a migration.

| Key | Type | Default |
|---|---|---|
| `appearanceMode` | String — `light` \| `dark` \| `system` | `system` |
| `colorLevel` | String — `full` \| `calm` \| `minimal` | `calm` |
| `identityColor` | String — `bronze` (petrol, slate later) | `bronze` |
| `fontFamily` | String — `Avenir` \| `System` | `Avenir` |
| `textScale` | Double — 1.0 … 2.0 | `1.0` |
| `setupFinished` | Bool | `false` |
| `demoMode` | Bool | `false` |
| `fullDiskAccessAsked` | Bool | `false` |

`setupFinished` is removed by the uninstaller, which is what makes setup run again after a
reinstall but not after an update.

## `WellkeptCore` — the shared vocabulary

```swift
public enum SectionID: String, CaseIterable, Sendable, Identifiable {
    case overview, hardware, storage, apps, security, backup, changes
    public var id: String { rawValue }
    public var title: String       // sidebar + page heading
    public var question: String    // the question it answers
    public var sentence: String    // the plain sentence on the face
    public var verb: String        // the one button
}

public enum SectionStatus: String, Sendable, CaseIterable {
    case good, needsAttention, notChecked
    public var label: String       // "Good" | "Needs attention" | "Not checked"
}

public enum Severity: String, Sendable, Comparable { case problem, attention, information }

/// A thing Wellkept found. `.problem` ONLY where something is actually wrong — a large folder
/// is not a problem, it is large.
public struct Finding: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let section: SectionID
    public let title: String       // what it is
    public let reason: String      // why it was flagged — always present, shown on the row
    public let severity: Severity
    public let measure: String?    // "4.2 GB", "83%", nil
    public let verb: String?       // the verb that sits on this row
}

/// One line of the audit trail: what was checked and when.
public struct CheckRecord: Sendable, Hashable {
    public let section: SectionID
    public let ranAt: Date
    public let status: SectionStatus
    public let complete: Bool      // false when a permission stopped us seeing everything
}
```

### The seven sentences — Claude's draft, John edits the words

| Section | Question | Sentence on the face | Button |
|---|---|---|---|
| Overview | Is my Mac OK? | Check everything, and say what needs you. | Check my Mac |
| Hardware | Is this machine healthy? | Read the drive, battery, memory and temperature, and report what they say. | Check hardware |
| Storage | What's eating my space? | Look at what is using the space on this Mac, largest first. | Scan storage |
| Apps | What's installed, and is it current? | List every app, where it came from, and whether a newer version exists. | Check apps |
| Security | Am I safe? | Check this Mac's protections, what can watch you, and what macOS has already found. | Check security |
| Backup | Is my stuff safe? | Check whether your files are backed up, and what is not covered. | Check backup |
| Changes | What changed, and who changed it? | Compare your settings against the last time we looked. | Check for changes |

## Decisions this shell is built to — do not relitigate

- Sidebar is **words, no icons**, fixed order, always visible, no counts or badges.
- Selected row: **soft bronze plate plus bolder words**.
- Bronze appears in exactly three places: selected sidebar row, the main button, section headings.
- Window opens 1,100 × 760, floor 1,020 × 640. Normal title bar. One window. Full screen allowed.
  Content column stays 700 pt and centres on a wide display.
- Closing the window quits (there is no menu-bar icon yet).
- Every section shows its **finished face with the real verb greyed out**, and one line
  underneath saying it is coming.
- The **Options** disclosure does not appear on a section with no options yet.
- Overview lists **only what needs you**, plus a "What was checked" disclosure listing all
  seven and when each ran. Clean state: "Everything looks fine" and the date. **Never a score.**
- Overview may **never** say the Mac looks fine when it could not see everything.
- Setup: welcome page → asks for Full Disk Access with a working **Finish later** → lands on
  Overview. Never demands. Never re-asks on its own. Re-runnable from Help.
- The word for something wrong is **problem**. Section status is **Good / Needs attention /
  Not checked**.
- No helper, no menu-bar icon, no widget, no notifications in this shell.
