# Prototypes (throwaway)

Browser mock-ups used to decide Turnover's interaction and look before writing the app.
Nothing here ships. Open any file in a browser; fake files only, nothing on disk is touched.

| File | Question | Verdict |
| --- | --- | --- |
| `ring-prototype.html` | How should the ring open? (A) drag + ⇧, (B) hold a key and flick, (C) tap a key and click | **A, drag + ⇧.** The ring only exists during a file drag, so it never clashes with Finder's ⇧ selection and needs no permission to read Finder's selection. |
| `ring-design-prototype.html` | Which visual style? Glass ring, floating pills, Finder icons | **Glass ring.** |
| `ring-glass-prototype.html` | Make it native: glass treatment, highlight, symbols, JPEG quality, mixed files | Regular glass, tinted-glass highlight that rotates to the option, text only (no symbols), edge refraction. JPEG quality is a setting (default High, 85%); hold **⌥** to fan JPEG out into Best / High / Small once. Mixed images + videos share one ring: **rest on a format to add it** (spring-loading, using the system delay), then drop on another. The hub previews the result. |
| `icon-prototype.html` | App icon direction: ring, page turn, photo → video, apple turnover | **A, the ring.** It mirrors the gesture: three glass segments, one lit. |
| `icon-a-prototype.html` | Ring icon colour, in macOS 26's default / dark / tinted appearances | **Blue**, matching the ring's highlight and the macOS accent colour. |

The original pastry icon was rejected as too weak.
