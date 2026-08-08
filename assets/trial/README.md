# PixelLab bounded visual trial

Run from the repository root using an Overseer-held key:

```sh
PIXELLAB_API_KEY='your PixelLab API key' node scripts/run-pixellab-trial.mjs
```

The script creates twelve PNGs and `provenance-manifest.json` here: Forge and
Tavern buildings, two citizen masters, four Kethra east-walk frames, and four
work-type glyphs. It refuses command-line arguments, reads the key only from
the environment, and never records it in output or logs.

Evaluate the generated contact set at 100%, 400%, and actual canvas scale:

- Style consistency across buildings, citizens, animation, and glyphs.
- Silhouette legibility at 1×, including the citizen's readable walk poses.
- Palette coherence across the full set.

The trial passes only if the Overseer accepts a usable candidate in every
category and can identify the walk-cycle frames as the same actor. The
provenance manifest records each generated asset's request identity, prompt,
seed, parameters, timestamp, and returned USD cost so it can be regenerated.
