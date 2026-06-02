# Proposals

Permanent registry of proposed changes to `MobileBandCheckup`. Every proposal that goes through any review — accepted, deferred, declined, even drafted-and-abandoned — gets an entry here so the decision and its reasoning survive past the conversation that produced it.

Append-only at the bottom for new entries. The **Status** line of an existing proposal is updated in place as it progresses; never delete or rewrite a proposal's body once others have seen it — add an entry to its **History** section instead.

## Status lifecycle

| Status | Meaning |
|---|---|
| **Draft** | Being written; not yet ready for a decision. |
| **Pending** | Written and ready for accept / defer / decline. The default state for a new proposal once it's complete enough to read. |
| **Accepted** | Approved; awaiting implementation. |
| **Done** | Implemented and merged. Include commit ref(s). |
| **Reverted** | Was implemented, then rolled back. Include both the implementing and the reverting commit refs and the reason. Keep the body; don't delete. |
| **Deferred** | Recognised but parked. Should have a note about *why* parked and what would unblock it. Eligible to be revived later — flip the Status back to Pending. |
| **Declined** | Decided against. Reason recorded. Stays in this file so the decision isn't re-litigated by accident. |
| **Superseded** | Replaced by a later proposal (link the new one). |

Every status change adds a **History** entry with the date, the new status, and (where appropriate) the commit ref.

## Required fields per proposal

- **Status:** one of the values above, with the date of the most recent change.
- **Author:** human name or "transitive from <source>".
- **Date opened:** `YYYY-MM-DD`.
- **Summary:** one paragraph, what & why in plain language.
- **Rationale:** why this is worth doing.
- **What changes:** concrete edits — file paths, line numbers, diff sketches.
- **Risk:** what could go wrong; blast radius.
- **Test plan:** how we'll know it worked.
- **Decision asked:** what the reader is being asked to approve/decline.
- **History:** chronological state-change log. Newest at the bottom.

## Optional fields

- **Alternatives considered:** other approaches and why they lost.
- **Related work:** links to upstream / downstream changes.
- **Upstream impact:** changes to `routeros_bundle` that this depends on or motivates.

## Numbering

Sequential, zero-padded to four digits: `P-0001`, `P-0002`, …. Numbers are never reused, even if a proposal is declined or superseded.

## Template

Copy this block for a new proposal. Replace placeholders, leave the section headers in place.

```markdown
## P-NNNN — <short imperative title>

**Status:** Pending (YYYY-MM-DD)
**Author:** <name or "transitive from …">
**Date opened:** YYYY-MM-DD

### Summary
One paragraph.

### Rationale
Why this matters; what breaks or stays suboptimal without it.

### What changes
Concrete edits with file paths and line numbers. Diff sketches where useful.

### Risk
Failure modes, blast radius, mitigations.

### Test plan
How we verify the change is good. Static, CI, on-device, whatever applies.

### Alternatives considered
(Optional) Other approaches and why they were rejected.

### Decision asked
What the reader is being asked to approve / decline / defer.

### History
- YYYY-MM-DD — opened, status Pending.
```

---

## P-0001 — Mirror `mbc3SaveState` function-value refactor post-mortem in this registry

**Status:** Done (2026-06-02) — reverted; lesson captured in HISTORY.md
**Author:** transitive from MobileBandCheckup code review (`4d22b92d-reviewh.txt`, review item #4)
**Date opened:** 2026-06-02

### Summary

The branch `claude/awesome-bohr-cMtgf` tried to factor the four duplicated inline state-save blocks in `MobileBandChange3.rsc` into a single shared function-value `mbc3SaveState`. On-router test wrote an empty `mbc3-state.txt` because RouterOS function-value name resolution is dynamic, not lexical: when `mbc3SaveState` called `mbc3BuildState`, the inner helper calls (`boolStr`/`intStr`/`escapeStr`) failed to resolve from inside the nested function-value scope. The refactor was reverted; the bundle's "four inline copies" pattern stays.

### What changed

- Refactor commit: `e1a91a0` (`mbc3-final-20260602-save-helper`).
- Revert commit: `b846183` (`mbc3-final-20260602-save-helper-revert`).
- One safety-fix from review item #3 — guarding `/file remove` with a length check — was kept after the revert. That's now the only divergence from the bundle's tested source.

### Lessons captured

- RouterOS function-value name lookup is dynamic against the caller's scope. Cross-function-value references work only when the caller and callee see the same enclosing `:local`s. Calling `[$mbc3BuildState]` from script-top works; calling it from inside another function-value does not.
- The bundle's apparent "code duplication" of the save block is a workaround for this language constraint, not a code-quality failure to be fixed.

### History

- 2026-06-02 — opened.
- 2026-06-02 — implemented as `e1a91a0`; on-device test failed (empty state file).
- 2026-06-02 — reverted as `b846183`; status **Done** (with the post-mortem as the deliverable; the safety fix from review item #3 kept separately).
- 2026-06-02 — root cause **corrected** via upstream `routeros_bundle/PROPOSALS.md#P-0003` (commit `19734ae` of branch `claude/dazzling-fermat-cCKGV`). RouterOS function-value name resolution is **lexical**, not dynamic as concluded above. The dedup refactor reverted in `b846183` likely failed because it moved the shared helper **further from** the inner `do={…}` call site (out of its lexical scope), not because of dynamic-resolution semantics. Empirical evidence: upstream observed empty values for every bool/int line in `mbc3-state.txt` while the three helpers (`boolStr`/`intStr`/`escapeStr`) lived at script-top as siblings to `mbc3BuildState`, then populated values immediately after the helpers were moved **inside** `mbc3BuildState do={…}`. Same-script inlining works; cross-script extraction does not. See `P-0003` below for the corresponding backport entry, which is the actual fix.

---

## P-0002 — Backport `/file remove` length guard upstream to `routeros_bundle`

**Status:** Pending (2026-06-02)
**Author:** transitive from MobileBandCheckup code review (`4d22b92d-reviewh.txt`, review item #3)
**Date opened:** 2026-06-02

### Summary

The defensive `[:len [/file find name=$sf]] > 0` guard before `/file remove` that landed in this repo's inline state-save blocks (commit `b846183`) is applicable verbatim to the upstream `routeros_bundle`'s seven equivalent save sites across `MobileBandChange3.rsc`, `tdhT.rsc`, and `wd5gT.rsc`. Filed upstream as `routeros_bundle/PROPOSALS.md#P-0001`. This entry is the downstream tracker; it transitions to **Done** when the upstream proposal lands and MobileBandCheckup's executable-line diff vs the bundle goes back to zero.

### Rationale

The guard already exists in this repo and is the **only** remaining divergence from the bundle's tested-on-hardware source. Pulling it upstream restores byte-equivalence and removes the standalone footnote from this repo's "tested transitively" claim.

### Upstream impact

- Upstream proposal: `routeros_bundle/PROPOSALS.md#P-0001`, branch `claude/awesome-bohr-cMtgf`, commit `39a6e5d`.

### Decision asked

Track the upstream proposal. If it lands, mark this **Done** and re-pull the bundle's runtime sources here (executable-line diff will be empty again).

### History

- 2026-06-02 — opened, status Pending (mirrors upstream P-0001).

---

## P-0003 — Inline `boolStr` / `intStr` / `escapeStr` inside `mbc3BuildState` (backport from upstream)

**Status:** Pending (2026-06-02)
**Author:** transitive from `routeros_bundle/PROPOSALS.md#P-0003` (commit `19734ae` of branch `claude/dazzling-fermat-cCKGV`).
**Date opened:** 2026-06-02

### Summary

Upstream `routeros_bundle` discovered and fixed an empty-save bug in `scripts/MobileBandChange3.rsc`'s persisted-state writer. The three helpers (`boolStr` / `intStr` / `escapeStr`) had been declared as `:local` at script-top and called from inside `mbc3BuildState do={…}` via `[$boolStr …]` / `[$intStr …]` / `[$escapeStr …]`. On RouterOS 7.21.4 those calls silently returned nothing — every `:set` line in `mbc3-state.txt` for a bool or int variable came out with no value, and the escapeStr-wrapped string lines only appeared populated because of the surrounding `$q . […] . $q` literal-quote wrapper.

The MBC `mbc3/MobileBandChange3.rsc` source traces to upstream b2.22 per PR #6's alignment claim and inherited the same buggy structure. Backport the fix: move the three helper bodies inside `mbc3BuildState`'s `do={…}` block; delete the outer definitions. Matches the pattern in `tdhT.rsc` and `wd5gT.rsc` (which already inline their `esc` copies).

### Rationale

Same as upstream P-0003 — the persisted state under the pre-fix code is functionally empty for all bool/int variables. Reads on restore set those globals to empty strings (typeof "str"); silent degradation rather than silent correctness. `mbc3HeartbeatEvery=""` in particular breaks the heartbeat arithmetic (empty in `($count % $every)` is undefined in RouterOS).

Correcting the wrong `P-0001` conclusion is the second deliverable — without it the next session that looks at the save block may try the same dedup refactor again and be confused when the dynamic-scoping hypothesis is still on the books.

### What changes

Single file: `mbc3/MobileBandChange3.rsc`. Move the three helper bodies inside `mbc3BuildState do={…}`'s body, delete the outer definitions, and update the section comment to reflect the new placement and the cross-`:do{}` rationale. Preserve the MBC-specific `/file remove` length guards. Same shape as upstream commit `19734ae`.

`PROPOSALS.md#P-0001` History gets one corrective entry (already added above).

### Risk

Low — same risk profile as upstream P-0003. Backwards/forwards compatible across save+restore because the restore-state allow-list accepts both empty and populated bare scalars; the first save under new code rewrites the file with populated values, healing the state in one cycle.

`mbc3QualityMonitor` was previously stuck at `""` (falsy str) so its branch was dead code. After this fix it will be honoured when set true. Same caveat as upstream.

### Test plan

| Layer | Action | Expected |
|---|---|---|
| Static | `grep -nE '^:local (boolStr\|intStr\|escapeStr) do=' mbc3/MobileBandChange3.rsc` | empty — none at script-top |
| Static | `grep -nE '^    :local (boolStr\|intStr\|escapeStr) do=' mbc3/MobileBandChange3.rsc` | three matches — all inside `mbc3BuildState` |
| On-device | Run `mbc3-cleanup` with `mbc3CleanupCommit=true`, then `/system script run mbc3-install`, then `/system script run MobileBandChange3` | New `mbc3-state.txt` has populated values: `mbc3Debug false`, `mbc3HeartbeatEvery 60`, `mbc3LastNrActive true`, `mbc3PendingLRsrpCount 0`, etc. |
| On-device | Reboot or `/system script run mbc3-restore-state` after a save | Restored globals have correct types: `[:typeof $mbc3HeartbeatEvery] = "num"`, not `"str"` |

### Related work

- Upstream proposal: `routeros_bundle/PROPOSALS.md#P-0003`, commit `19734ae`, branch `claude/dazzling-fermat-cCKGV`.
- Source brief: `routeros_bundle/audit/p0003-mbc-backport-brief.md`.

### Decision asked

Approve / defer / decline. Same decision pattern as upstream P-0003.

### History

- 2026-06-02 — opened, status Pending. Backport of upstream `routeros_bundle/PROPOSALS.md#P-0003`. Empirical evidence collected upstream; this entry tracks the downstream port.
