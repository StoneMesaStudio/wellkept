# Wellkept — the Changes section: findings and decisions

2026-08-28. Six agents, reading only. **Nothing on this Mac was written**, no setting was changed,
and nobody was contacted.

## The two findings that change the plan

### 1. "Put it back" rests on a premise that no longer exists

John approved put-it-back on **2026-08-25**, on one clause: it *"needs the privileged helper we
already have."* **No privileged helper ships any more.** And the measurement collapses the two
categories he approved into one:

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
- **383 of his 787 descriptions are flagged AI-generated**, and 580 entries came from users. What
  is genuinely his is the pipeline, the judgement and eleven weeks of corrections. His crowd is
  what feeds it. **We have no crowd** — that is the MacUpdater failure mode, which we already
  refused once.

## What was measured

| Finding | Consequence |
|---|---|
| **A full settings snapshot costs 0.77 seconds and 63 KB.** A year of daily snapshots is 23 MB. | Taking one every time the app opens is free. No schedule needed, no LaunchAgent, no notification. |
| **An idle Mac changed 40 values in six minutes — and not one was a setting.** All of it was daemon bookkeeping, confined to about ten nameable domains. | The noise is real, small, and nameable. Exclude by domain. |
| **We can say WHEN. We can never say WHO.** Nothing unprivileged records which process wrote a setting, and the log that might forgets within a day. | ⚠️ Naming an app as the culprit would be defaming somebody's software on no evidence. We never do it. |
| **The strongest honest sentence available**: "this changed while your Mac was off for the macOS 26.6.2 update — it was off for four minutes and 52 seconds." Ten of eleven updates here land within two minutes of a recorded boot. | That is the claim, and its wording is deliberate: *changed during*, never *the update changed it*. |
| **A restart is not evidence of an update** — 15 of this Mac's 25 boots carried none. | Never use a reboot as a proxy. |
| **The install record is world-readable, 110 entries deep, and its dates are in UTC.** macOS 26.6.2 reads as 25 August and happened on the evening of the 24th. | Read it wrong and every update lands on the wrong day. |
| **File timestamps are worthless as evidence** — three quarters of the preference files here were rewritten in a day by daemons. | Compare values, never dates. |
| **The command that lists settings domains omits the most important one** — appearance, accent colour, text size, key repeat, scroll direction. | Add it by name or silently miss the most visible settings on the Mac. |
| **The plan's showcase example cannot be answered.** Safari keeps its settings in a container we are banned from reading; same for Mail, Photos, Messages, Notes. The default browser can be answered. | Say what we cover, plainly. |
| **On a standard account the boot log is unreadable.** The section still knows an update happened and when; it loses the ability to say the Mac was off. | Which is exactly the evidence that made the claim strong. Weaker wording there. |
| **Nothing in Changes needs the network.** | It adds no new entry to the privacy register — provided we never fetch anybody's descriptions at launch. |

## Asked of John

| # | Question | Answer |
|---|---|---|
| 1 | Does Changes ever write a setting back, or only show and open the right pane? | |
| 2 | How far do we go on SetShot before anyone has written to Adam Engst? | |
| 3 | On uninstall, do the settings snapshots go quietly, or does it stop and ask? | |
| 4 | Without Full Disk Access we can see THAT privacy permissions changed but not what. Show that row, or say nothing? | |
