---
name: magic-time
description: Turn a time in plain English into Discord timestamp codes (<t:UNIX:STYLE>, "magic time", "hammertime") using the local `magic-time` command, which shares the Magic Time app's parser. Use this whenever someone asks for a Discord timestamp, magic time, a <t:…> code, a time "everyone sees in their own time zone", or wants to schedule/announce a raid, stream, game night, or meeting for a Discord server — even if they just say "what's 9:30 eastern tomorrow in discord time" or paste a time and ask for the code. Also use it to decode a pasted <t:…> code or Unix timestamp back into a readable date, and for holiday-relative times like "lunar new year 7pm PT", "3rd friday in may at 6pm", or "diwali 8pm".
---

# Magic Time

Discord renders `<t:SECONDS:STYLE>` in each reader's own time zone. `SECONDS` is a Unix time, and
getting it wrong by an hour (DST, a misread zone, the wrong day) silently sends a whole server to
the wrong event. So don't compute it in your head or with ad-hoc date math: run the `magic-time`
command, which is the same parser the Magic Time app uses and is tested against hundreds of
phrases, holidays across calendars, and almanac data.

## Run it

```bash
magic-time "<the user's phrase>" [--zone local|eastern|pacific|london|tokyo|…|utc|<IANA id>] [--format F|f|s|t|R|D|d|T|S] [--json]
```

- Pass the user's wording as-is ("tomorrow 9:30am", "fri 8pm PT", "3rd friday in may at 6pm",
  "christmas eve 7pm", "in 2 hours"). The parser handles typos like "tmrw", ranges like "6-8pm",
  and zones written in the text ("PT", "eastern", "london"), which override `--zone`.
- Use `--zone` when the user states the zone separately ("9:30, eastern time" → `--zone eastern`)
  or it's clear from context. Without it, the Magic Time app's chosen zone is used (this Mac's own zone by default). `--zone` also takes `local` and city names such as `london` or `tokyo`.
- Use `--format` when they want one specific look; otherwise show the useful few.
- If `magic-time` isn't on PATH, build it: `cd ~/Projects/magic-time && ./build.sh` (installs to
  `~/.local/bin`). If the project isn't there, say so instead of falling back to manual math.

## Read the result

The exit status tells you which of three things happened:

| Exit | Meaning | What to do |
|---|---|---|
| 0 | Found a moment. Output starts with `Read as …` | Give the codes. Mention the "Read as" date so the user can catch a misread (for example, an assumed AM/PM). |
| 2 | `Won’t guess: …` — a holiday whose date isn't agreed on (Vesak, a bare "Eid", Holi 2027) | Relay the note in your own words and ask which date they mean. Don't pick one yourself. |
| 1 | No date or time found | Say so and ask them to rephrase with a day and time. Don't guess what they meant. |

This "never guess" behavior is deliberate: a missing answer costs the user one more message; a
confidently wrong timestamp costs everyone who shows up at the wrong time.

## Answer format

Lead with the code they'll most likely paste, in a code block so it copies cleanly, then a short
table of alternatives. Example for "tomorrow 9:30am eastern":

```
<t:1790947800:F>
```

| Code | Shows as (for an Eastern reader) |
|---|---|
| `<t:1790947800:F>` | Friday, October 2, 2026 at 9:30 AM |
| `<t:1790947800:t>` | 9:30 AM |
| `<t:1790947800:R>` | in 18 hours (a live countdown) |

Previews are what *this* Mac's locale shows; each Discord reader sees their own time zone and
format. `f` is Discord's default style if the letter is left off.

If the user is already talking about an earlier code (for example, "make that tomorrow instead"),
rerun the command with the new phrase rather than adding 86400 by hand: DST changes and month
boundaries are exactly where hand math slips.
