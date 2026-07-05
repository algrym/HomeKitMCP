# Known Limitations

Things this server intentionally does **not** do, with the reasoning, so they don't get
re-investigated. This server is a thin wrapper over Apple's **HomeKit.framework**
(`HMHomeManager` and friends) — it can only expose what that framework exposes.

---

## Favorites / "Include in Home View" cannot be toggled

**Status:** Not possible. Not a missing feature — an Apple API gap. Do it manually in the Home app.

The Home app's **Favorites** flag (formerly "Include in Home View") — the toggle that controls
which accessories appear on the Home app's top page — is **not reachable through any public
API**, so there is no tool for it and there can't be one without Apple exposing it.

### Why (verified against the API, not assumed)

- **Not on `HMAccessory`.** Full member list is `blocked, bridged, cameraProfiles, category,
  firmwareVersion, identifier, manufacturer, model, name, profiles, reachable, room, services,
  supportsIdentify, uniqueIdentifier, …` + methods `identify`, `updateName`. No favorite/visibility member.
- **Not on `HMService`.** Full property list is `accessory, associatedServiceType, characteristics,
  linkedServices, localizedDescription, name, primaryService, serviceType, uniqueIdentifier,
  userInteractive`. No favorite/visibility member.
- **Not anywhere in the SDK.** Grepping the HomeKit.framework headers in the Xcode SDK
  (62 headers) for `favorit|includeinhome|homeview|isVisible` returns **zero matches**.

Favorites are stored as the **Home app's own preference metadata** (iCloud-synced), not as a
property on the HomeKit object graph. Apple has kept "Include in Home View" a manual, per-accessory
UI gesture for the life of the framework.

### False friends (do not chase these)

- `HMService.primaryService` — "primary service among linked services" (which service represents a
  multi-service accessory). **Not** the Home-View favorite.
- `HMHome.isPrimary` — the primary **home**. Unrelated.

### Bridged accessories don't help

For a HomeKit setup fed by a Home Assistant HomeKit Bridge, favorites are still an **Apple-Home-side**
preference regardless of source. Home Assistant cannot set them either — there is no backdoor through
the bridge.

### Why not drive the Home app via AppleScript / Apple Events?

Two flavors, both ruled out:

1. **Real Apple Events to a scriptable Home app — impossible.** The macOS Home app ships **no
   scripting dictionary** (no `NSAppleScriptEnabled`, no `.sdef`). It understands only `activate`/`quit`;
   there is no accessory or favorite vocabulary to send.
2. **GUI scripting (System Events faking clicks) — technically possible, rejected.** It works by
   puppeting the accessibility tree, but from this server it is impractical and brittle:
   - Requires **Accessibility (TCC) consent** for the controlling process — a plain `osascript` →
     System Events call fails today with `-1728 "not allowed assistive access"`. Granting that to a
     pipe-launched, path-versioned binary is fragile and re-prompts whenever the binary moves/re-signs.
   - Requires **Automation consent**; a headless background subprocess triggering it is unreliable
     (often fails `-1743` instead of prompting, due to no clean UI attribution).
   - Requires the Home app **foregrounded and navigated** — launch it, find the one tile among all
     accessories, open its settings popover, flip the toggle. The Catalyst AX tree reshuffles on every
     Home app update, window resize, and locale.
   - It is **loud** — the Home app pops to the foreground and gets driven on-screen, defeating the
     server's headless design.

   If this is ever genuinely wanted, the least-bad shape is a **separate, user-launched helper** (a
   normal foreground app run deliberately, with Accessibility granted once) that does a one-shot
   "favorite these N accessories" pass — keeping the brittle UI automation out of the always-on server.
   Even then it is UI scraping and will rot. Not recommended.

3. **Shortcuts is not a backdoor either.** HomeKit's Shortcuts actions cover running scenes and
   controlling accessories; favorites are not among them.

**Bottom line:** set favorites by hand in the Home app (long-press an accessory → settings →
"Include in Home View"). It is the one piece of home organization Apple does not let apps touch.
