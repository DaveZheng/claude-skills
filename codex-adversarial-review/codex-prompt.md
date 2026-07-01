Perform an adversarial code review of the current change in two internal passes.

Scope: $ARGUMENTS
(If no scope is given, review the uncommitted changes — run `git diff HEAD` and read the touched files for context. If a branch or commit is named, review that instead.)

PASS 1 — FIND. Read the actual code (not just the diff hunks) and hunt for real defects introduced or exposed by the change, across these dimensions: correctness, security, data-integrity/concurrency, performance, and API/type-contract. For each candidate note file:line, severity, why it's wrong, and a concrete failure scenario (inputs/state → wrong outcome).

PASS 2 — REFUTE. Now switch sides and attack each candidate. For every finding, try hard to prove it wrong: is the code actually doing what you claimed? Can the failure scenario really occur, or does a guard elsewhere prevent it? Is it pre-existing / out of scope? Drop any finding you cannot concretely confirm reproduces against the real code. Default to dropping when uncertain.

Report only the survivors, most severe first. For each: `[SEVERITY] title`, `file:line`, why, and the confirmed failure scenario. If nothing survives, say so plainly — do not invent findings to fill space. Do not edit files; this is read-only.
