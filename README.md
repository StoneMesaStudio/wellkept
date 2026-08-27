# Wellkept

### A health check for your Mac.

Wellkept looks at a Mac and tells you what it finds — the drive, the battery, what is using
your space, what is installed and out of date, what protections are on, whether your files are
backed up, and what changed on your Mac without you.

**It does not delete anything.** Everything it removes goes to a quarantine you can browse, with
thirty days to change your mind. Machine junk — caches, logs, old installers — may be
pre-selected, because it regenerates itself. Your own files never are: the job is to reveal, not
to clean.

**Nothing is collected and nothing is sold.** No account, no identifier, no analytics, no
marketing list. Two things leave this Mac, both disclosed and both switchable: a check for newer
versions of your apps, and a check for a newer Wellkept. Switching one off costs you that feature
and nothing else.

The exact words are in `Core/Sources/WellkeptCore/Privacy.swift`, which is the one place in the
app allowed to make a claim about what leaves this Mac. Anything that leaves and is not registered
there does not ship.

Free, open source, GPL-3.0. Not on the Mac App Store — it cannot be, because a sandboxed app
cannot read other apps' files, cannot run a privileged helper, and cannot back up a volume.

---

Stone Mesa Studio, LLC · macOS 14 and later · Apple Silicon and Intel
