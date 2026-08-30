# Wellkept — the Changes section: findings and decisions

2026-08-28. Six agents, reading only, measured on a real Mac during development. **Nothing was
written**, no setting was changed, and nobody was contacted.

## The two findings that change the plan

### 1. "Put it back" rests on a premise that no longer exists

Put-it-back was approved on **2026-08-25** on a single clause — that it needed only the privileged
helper the plan assumed already existed. **No privileged helper ships any more.** And the
measurement collapses the two approved categories into one:

| Of the seven things the plan wants to put back | Can we write it? |
|---|---|
| Default browser | ✅ documented call, no password, macOS puts up its own confirmation |
| Firewall · sharing · Gatekeeper · FileVault · automatic updates · privacy grants | ❌ root, an admin password dialog, or Recovery |

- **Privacy permissions can never be put back at any privilege.** There is no supported write; the
  only tool resets everything rather than restoring one thing.
- Even where a write succeeds, Apple's own documentation says a running app may not notice and may
  overwrite it — and Dock, Finder, Control Center and loginwindow are always running. **A write
  that reports success and changes nothing is the worst outcome available.**

### 2. The valuable half of SetShot is not licensed to us

- The **app** is MIT and may be reused with attribution. But **the diff engine is about 60 lines**;
  it was never the hard part.
- **The plain-English descriptions live in a second repository, `adamengst/setshot-kb`, which has
  no LICENSE file and no licence metadata** — verified directly. By default that is all rights
  reserved. Copying, bundling, adapting or fetching it is not permitted today, and folding it into
  a GPL-3.0 app would be worse, because we would be passing it on.
- **383 of the 787 descriptions there are flagged AI-generated**, and 580 entries came from users.
  What is genuinely the author's is the pipeline, the judgement and eleven weeks of corrections —
  and a crowd feeding it. **We have no crowd** — that is the MacUpdater failure mode, which we
  already refused once.

## What was measured

| Finding | Consequence |
|---|---|
| **A full settings snapshot costs 0.77 seconds and 63 KB.** A year of daily snapshots is 23 MB. | Taking one every time the app opens is free. No schedule needed, no LaunchAgent, no notification. |
| **An idle Mac changed 40 values in six minutes — and not one was a setting.** All of it was daemon bookkeeping, confined to about ten nameable domains. | The noise is real, small, and nameable. Exclude by domain. |
| **We can say WHEN. We can never say WHO.** Nothing unprivileged records which process wrote a setting, and the log that might forgets within a day. | ⚠️ Naming an app as the culprit would be defaming somebody's software on no evidence. We never do it. |
| **The strongest honest sentence available**: "this changed while your Mac was off for the macOS 26.6.2 update — it was off for four minutes and 52 seconds." Ten of eleven updates here land within two minutes of a recorded boot. | That is the claim, and its wording is deliberate: *changed during*, never *the update changed it*. |
| **A restart is not evidence of an update** — 15 of 25 boots on the measured Mac carried none. | Never use a reboot as a proxy. |
| **The install record is world-readable, 110 entries deep, and its dates are in UTC.** macOS 26.6.2 read as 25 August and happened on the evening of the 24th. | Read it wrong and every update lands on the wrong day. |
| **File timestamps are worthless as evidence** — three quarters of the preference files measured were rewritten in a day by daemons. | Compare values, never dates. |
| **The command that lists settings domains omits the most important one** — appearance, accent colour, text size, key repeat, scroll direction. | Add it by name or silently miss the most visible settings on the Mac. |
| **The plan's showcase example cannot be answered.** Safari keeps its settings in a container we are banned from reading; same for Mail, Photos, Messages, Notes. The default browser can be answered. | Say what we cover, plainly. |
| **On a standard account the boot log is unreadable.** The section still knows an update happened and when; it loses the ability to say the Mac was off. | Which is exactly the evidence that made the claim strong. Weaker wording there. |
| **Nothing in Changes needs the network.** | It adds no new entry to the privacy register — provided we never fetch anybody's descriptions at launch. |

## The four open questions, and how they were decided

| # | Question | Answer |
|---|---|---|
| 1 | Does Changes ever write a setting back, or only show and open the right pane? | **Show what changed and open the correct pane** (decided 2026-08-28). **Wellkept writes no setting at all** — I am dropping the default-browser exception I recommended, because one lone writable row is an inconsistency a person has to learn, and the section is cleaner without it. Changes reads and explains; System Settings does the changing. |
| 2 | How far do we go on SetShot before anyone has written to Adam Engst? | **None of his material. Ours, and better** (decided 2026-08-28). No code, no descriptions, no data, no fetching. Credit him as prior art in the Help page as a courtesy, not as a licence obligation — with nothing of his in the app, we owe none. **Scope: only the settings Wellkept already reads across Hardware, Security, Apps and Storage.** A few dozen sentences we can stand behind, not 787 we cannot maintain. **What "better" means concretely**, since his are half AI-generated one-liners: each description says what the setting does, **what turning it off actually costs you**, and **why it might have changed** — three things his knowledge base does not attempt. |
| 3 | On uninstall, do the settings snapshots go quietly, or does it stop and ask? | **Ask, with three buttons** (decided 2026-08-28): leave them where they are · save them to a folder you pick · delete them. Saved copies are a readable summary **and** the raw file, so they are useful without Wellkept. "Leave them" matters because somebody reinstalling next month gets their history back. |
| 4 | Without Full Disk Access we can see THAT privacy permissions changed but not what. Show that row, or say nothing? | **Show it**, once, as a single line with the button that grants access, and never repeated per permission. Saying nothing would be reporting zero because we could not look, which the app has banned everywhere else. |

## Scope, settled 2026-08-28 — and it is smaller than the plan

The general settings-change journal was held back. Implementing it meaningfully is a great deal of
work for what it returns, and it is the half worth revisiting in a later release — ideally after
talking to Adam Engst and getting his consent to roll his curated list into the package.

**So the section splits in two:**

| Ships in version one | Deferred to version two |
|---|---|
| Diffing **what Wellkept already understands** — FileVault, firewall, Gatekeeper, sharing services, login items, configuration profiles, privacy grants — because those readers already exist in `App/Security/`. This is the malware-adjacent half the plan was excited about: *a configuration profile appeared on Thursday; Zoom gained Screen Recording on Tuesday.* No knowledge base needed. | The **general settings journal** across hundreds of domains. That is the part that needs a curated description for every key, which is the MacUpdater trap — a database somebody feeds forever. It is also the part worth talking to Adam Engst about, because his curated list is exactly what it needs. |
| **macOS update attribution** — "this changed while your Mac was off for the macOS 26.6.2 update, and it was off for four minutes and 52 seconds." | |
| **The snapshots themselves, in full, from first launch.** They cost 0.77 seconds and 63 KB. **A record cannot be back-filled** — the same argument as Hardware's reading history. Capture everything now, describe only what we understand, and version two arrives with a year of history in hand rather than starting empty. | |

**Consequence for the seven sections:** Changes still ships, and still answers its question. It
answers it about the things Wellkept watches rather than about every preference on the Mac, and the
face says so plainly rather than implying it watched everything.
