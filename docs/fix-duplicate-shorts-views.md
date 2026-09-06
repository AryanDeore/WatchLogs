# Fix: Duplicate Views for YouTube Shorts

## Issue

YouTube Shorts (and similar video feeds) create multiple `<video>` DOM elements simultaneously:
- One for the currently visible short
- Others for preloaded adjacent shorts (next/previous)

When all elements fire their `loadedmetadata` events at nearly the same time, the extension was creating separate Views for each element, even though they represent the same video.

### Observed Symptoms

Database showed:
```sql
-- 3 Views for "can we dunk?" at exactly 04:03:34
011e2d13... | U-hMbrAlo-Y | tab:1751766412 | 2026-09-06 04:03:34 | 1 segment, 0 watched
17003445... | U-hMbrAlo-Y | tab:1751766412 | 2026-09-06 04:03:34 | 1 segment, 1 watched (13.8s)
8757e021... | U-hMbrAlo-Y | tab:1751766412 | 2026-09-06 04:03:34 | 1 segment, 0 watched
```

Result: 3 Views with same `video_id`, `tab_id`, and `started_at_ms`, but different `view_id`s. Only one had watched time, the others had zero.

## Root Cause

The `ensureView()` function in `content.js` has a sharing check to prevent duplicate Views when an Adapter is bound:

```javascript
const sharing = bound.adapter
  ? [...tracked.values()].find((open) => open.key === header.videoId && isOpen(open.viewId))
  : undefined;
```

This works when events are processed sequentially:
1. Element 1 fires → creates View → adds to `tracked` 
2. Element 2 fires → finds Element 1 in `tracked` → reuses its `viewId`
3. Element 3 fires → finds Element 1 in `tracked` → reuses its `viewId`

But when all 3 elements fire `loadedmetadata` simultaneously at the same moment (e.g., when the page loads), the first element hasn't been added to `tracked` yet when subsequent elements check.

## Solution

Added a `pendingOpens` map that tracks Views being opened **during** the `ensureView` call:

```javascript
const pendingOpens = new Map(); // videoId -> viewId

// In ensureView():
const sharing = bound.adapter
  ? [...tracked.values()].find((open) => open.key === header.videoId && isOpen(open.viewId)) ||
    (pendingOpens.has(header.videoId) ? { viewId: pendingOpens.get(header.videoId) } : undefined)
  : undefined;

if (!sharing) {
  pendingOpens.set(header.videoId, entry.viewId);
  apply(capture, { type: "OPEN", at: fact.at, viewId: entry.viewId, view: header });
}
```

Now when multiple elements for the same video call `ensureView` nearly simultaneously:
1. Element 1: No match in `tracked` or `pendingOpens` → creates `viewId1` → adds to `pendingOpens`
2. Element 2: Finds `viewId1` in `pendingOpens` → reuses it
3. Element 3: Finds `viewId1` in `tracked` (Element 1 completed) → reuses it

## Cleanup

`pendingOpens` entries are removed when:
- A View ends (`VIEW_ENDED`)
- A View changes to a different video (`CHANGE_VIDEO`)

This prevents the map from growing without bound over the life of the page.

## Testing

### Unit Tests
All existing unit tests pass (`npm test`).

### E2E Test
Added `test-e2e/content.spec.js` test:
- Loads `youtube-shorts-sim.html` with 3 `<video>` elements for same video
- Verifies only 1 View is created
- Verifies only 1 `mediaFound` event
- Verifies playing samples are recorded

Run with: `npm run test:e2e`

## Impact

- **Fixed**: Duplicate Views for same video in YouTube Shorts
- **Preserved**: Existing behavior for:
  - Non-Adapter sites (each element gets its own View)
  - Sequential event processing (already worked)
  - Ad/content separation (pre-roll ads still share the video's View)

## Related Issues

Similar to (but distinct from) issue #42 which addresses hover previews on the YouTube home feed. This fix addresses multiple simultaneous elements for the **same** video, while #42 addresses unwanted Views for **different** videos (previews).
