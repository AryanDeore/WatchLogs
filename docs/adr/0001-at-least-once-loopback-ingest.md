# At-least-once loopback ingest, de-duplicated downstream

The Extension Flushes buffered Events to the App over loopback HTTP and holds each batch on disk until it sees an ack. When the ack is lost (laptop sleeps mid-response, wifi blips, the App is slow), the Extension cannot tell "the App never received it" from "the App received it and the reply vanished", so it resends. We decided the App accepts this: `POST /v1/flush` is **at-least-once**, the App keeps no memory of batches it has already seen, and duplicate raw Events are removed downstream in Segment computation by keying on stable Event ids.

## Considered options

- **Exactly-once at the front door.** The App remembers recently-seen batch ids and, on a resend, returns `200` without storing anything. Rejected: it needs an expiry policy on that "seen" set that can itself be wrong (too short re-admits duplicates, too long is unbounded memory), and it still depends on stable batch ids from the message schema — so it adds a second, failure-prone mechanism without removing the need for the first.
- **Drop-on-doubt in the Extension.** The Extension only resends when it is sure the App did not receive the batch. Rejected: that certainty does not exist over a connection that can drop the response, so this silently loses data in exactly the offline scenario the buffer exists to cover.

## Consequences

- The message-schema work (issue #2) must define a stable per-batch id and stable per-Event ids that do not change on resend.
- Segment computation (issue #6) must be idempotent under duplicate raw Events: de-duplicate on Event id before deriving Segments, so a re-delivered batch does not inflate Watched time. This is distinct from the domain rule that genuinely re-watched spans count twice — those are different Events at different wall-clock times.
- `raw_events` is an append-only log that may legitimately contain the same Event twice; consumers never assume uniqueness.
