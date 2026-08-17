# WhatAMess — Filter Prototype

Prototype fork of [OaksTheAwesome/WhatAMess](https://github.com/OaksTheAwesome/WhatAMess) that adds
an iOS 26-style filter button to the Messages conversation list. Everything from upstream 1.3 is
untouched; the filter feature lives in separate files.

## What this fork adds

- **Filter button** in the conversation list nav bar, immediately to the left of the compose button.
- **Filter menu** matching the iOS 26 layout: Messages, Unknown Senders, Transactions (with Orders /
  Finance / Reminders submenu), **2FA**, Promotions, Spam, Recently Deleted, then Manage Filtering
  below a divider. The active filter carries a checkmark; each category shows a sender count.
- **Manage Filtering** — a searchable list of every sender Messages has shown you. Search by name or
  by digits (`4125854255` matches `+1 (412) 585-4255`), tap a sender to move it into a filter, swipe
  to forget it, or add a number by hand with `+`. Reachable from the in-app menu and from
  Settings → WhatAMess → Filter Button → Manage Filtering.
- **Automatic categorisation** for senders you haven't assigned: numeric short codes whose latest
  message looks like a passcode land in 2FA, other unsaved numbers land in Unknown Senders. A manual
  assignment always wins.
- **Enable Filter Button** toggle in Settings, in a new Filter Button section under Cell Settings.

### How the filtering works, and what it can't do

iOS 17 has no OS-level filter folders beyond Unknown Senders, and no API to route a message into a
category. So this is client-side: the tweak keeps its own sender-to-category map in the existing
WhatAMess plist and hides non-matching cells in the conversation list, compacting the remaining ones
upward so there are no gaps.

Two consequences worth knowing before you file a bug:

1. **The roster fills as you scroll.** A sender is only recorded once its cell has been on screen at
   least once. Open Messages and scroll the list top to bottom once to populate Manage Filtering.
2. **A filter only shows conversations the list has already loaded.** With a filter active, matching
   conversations further down the list appear as you scroll. If nothing matches yet you get an empty
   state saying so rather than a blank screen.

`Recently Deleted` probes for the system's own Recently Deleted view and falls back to telling you to
use Edit → Show Recently Deleted if it can't find it on your iOS version.

## Files added by this fork

| File | Role |
| --- | --- |
| `WAMFilterModel.h/.m` | Category enum, plist-backed assignments and sender roster, matching rules, heuristics. Compiled into both binaries. |
| `WAMManageFilteringController.h/.m` | The searchable sender list and per-sender category picker. Compiled into both binaries. |
| `WAMFilterTweak.x` | Hooks: nav bar button, menu construction, cell hiding, layout compaction. |
| `.github/workflows/build.yml` | Builds the rootless deb on push and attaches it to a release. |

New preference keys, all in `com.oakstheawesome.whatamessprefs.plist` alongside the existing ones:
`isFilterButtonEnabled`, `filterActiveSelection`, `filterAssignments`, `filterRoster`.

## Building

CI does it on every push to `main` — the deb lands in the run's artifacts and in a
`build-<number>` release. To build locally with Theos:

```
export THEOS_PACKAGE_SCHEME=rootless
make package FINALPACKAGE=1
```

Tested target: iOS 17.0, iPhone 13, Dopamine 3 (rootless). Upstream compatibility is unchanged —
rootless jailbreaks on iOS 15 through 18.

The package identifier stays `com.oakstheawesome.whatamess` at version 1.4.0, so installing this
upgrades over upstream 1.3 in place rather than injecting twice. Reinstall upstream to go back.
