# PixelLab bounded visual trial

Run from the repository root using an Overseer-held key:

```sh
read -rs PIXELLAB_API_KEY && export PIXELLAB_API_KEY
node scripts/run-pixellab-trial.mjs
```

To request a fresh candidate set without changing source, set an integer seed
offset before running it (for example, `PIXELLAB_SEED_OFFSET=1 node
scripts/run-pixellab-trial.mjs`). The offset is added to every fixed card seed
and recorded in the manifest's resulting seed values.

`PIXELLAB_TIMEOUT_MS` overrides the request timeout and **applies to both
endpoints uniformly**: the defaults are 30s for single images and 120s for the
four-frame animation call, so do not set it below `120000` — a too-tight bound
can be billed server-side and aborted client-side (Warden doj finding 1). Walk
entries in the manifest carry a `frameIndex` field (1–4) and share one truthful
animation prompt; the frame identity lives in the id and `frameIndex`, not in
the prompt text.

The script creates twelve PNGs and `provenance-manifest.json` here: Forge and
Tavern buildings, two citizen masters, four Kethra east-walk frames, and four
work-type glyphs. It refuses command-line arguments, reads the key only from
the environment, and never records it in output or logs.

Evaluate the generated contact set at 100%, 400%, and actual canvas scale:

- Style consistency across buildings, citizens, animation, and glyphs.
- Silhouette legibility at 1×, including the citizen's readable walk poses.
- Palette coherence across the full set.

The walk cycle is generated in one request from the saved Kethra citizen master,
so its four frames carry that master as a PixelLab reference rather than being
independent text-to-image generations. The trial passes only if the Overseer
accepts a usable candidate in every category and can identify the walk-cycle
frames as the same actor. The provenance manifest records each generated
asset's request identity, prompt, seed, parameters, timestamp, returned USD
cost, source reference hash (where applicable), and PNG SHA-256 so it can be
regenerated and checked.

`assets/trial/` is deliberately committed: its sprites are the product of this
bounded trial, and its manifest is their provenance record.
