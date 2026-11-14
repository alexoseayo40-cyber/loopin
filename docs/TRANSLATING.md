# Translating Loopin

All the app's texts live in one JSON file per language in [`app/assets/l10n/`](../app/assets/l10n/):

| File | Language | Status |
|---|---|---|
| `es.json` | Spanish | **Reference** (the original) |
| `en.json` | English | Reviewed |
| `fr.json` | French | Draft — needs a review by a native speaker |
| `de.json` | German | Draft — needs a review by a native speaker |
| `it.json` | Italian | Draft — needs a review by a native speaker |
| `pt.json` | Portuguese (Brazil) | Draft — needs a review by a native speaker |

The app follows the phone's language (the first one in the phone's list that Loopin has; otherwise English), and it can be changed in Settings › Language.

The store listings (F-Droid, IzzyOnDroid) are in [`fastlane/metadata/android/`](../fastlane/metadata/android/), one folder per language.

## The format

Each file is a flat JSON object: a key and its text. Keep the keys, translate the texts. The files can be loaded into [Weblate](https://weblate.org) as a "JSON file" component with `es.json` as the source and the "ICU MessageFormat" check turned on.

```json
"trackLabel": "TRACK {n}",
"bars": "{n, plural, one {# bar} other {# bars}}",
```

- **`{name}`** is filled in by the app (a number, a name…). Keep every `{name}` of the Spanish text, with the same name. You can move it.
- **`{n, plural, one {…} other {…}}`** picks the text by number; `#` is the number. `other` is always required. Use the categories your language needs (`one`, `other`; `=0` for an exact number). In French and Portuguese, 0 and 1 are `one`.
- **Apostrophes are plain text** (they don't escape anything). Curly ones (’) are fine too. Braces `{ }` can't be used as text.
- **` `** is a non-breaking space (for example, before `:` in French, or in `70 %`).
- `format.decimal` is the decimal separator of your language and `format.percent` how a percentage is written.
- `date.month.1` … `date.month.12` are short month names; `date.dayMonth` and `date.dayMonthYear` put the day, month and year in your order.
- Note names (`note.0` = C … `note.11` = B): letters in English and German (`H` for B in German), do-re-mi in the others. Always with `#`, never `♯` (the fonts don't have it).

`app/test/l10n_test.dart` fails if a file is missing a key or has one too many, if a text is badly written, or if it doesn't use the same `{names}` as Spanish.

## Short texts

Many texts sit on the pedal face, which doesn't scroll: keep them about as short as the Spanish ones. The tests check that everything fits on a 360 × 640 phone with large text, but a shorter word is always better than a squeezed one. The main ones:

- States under the button: `ready`, `waiting`, `getReady`, `playing`, `stopped`, `stoppingAtOne`, `fadingOut`, `recordingTitle`, `overdubTitle`
- Tempo display: `tapTempo`, `tempoLocked`, `tempoFromLoop`, `trainerPill`, `loopModeShort.*`, `barsShort` (one letter for "bar": `4 B`)
- Bottom bar: `undo`, `stop`, `start`, `monitor`
- Drums and song row: `accDrums`, `accSong`, `drumChip.*`, `songChoose`, `songSetup`, `songTooFar`, `songFailedChip`
- Tracks: `trackLabel`, `reverseShort`
- Tuner: `tunerInTune`, `tunerFlat`, `tunerSharp`, `note.*`

## Style

- Short and plain: one line per option, the long explanation behind the "?" (the `…Help` texts).
- Talk to the musician directly (in French "vous", in German "du", in Italian "tu", in Portuguese "você").
- "The 1" is the first beat of a bar ("on the 1").
- Not translated: the "Copy results" report (it's in Spanish when the app is in Spanish, and in English otherwise), "BPM", "REV", "½", "TAP", "SYNC" and the time signatures.

## Trying it out

```sh
cd app
flutter test test/l10n_test.dart   # keys, parameters and that everything fits
flutter run                        # then Settings › Language
```
