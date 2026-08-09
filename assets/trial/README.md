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

`PIXELLAB_TIMEOUT_MS` is a per-endpoint timeout floor: both the single-image
Pixflux request and the four-frame animation call default to 120s, and an
override below `120000` cannot shorten either endpoint. Higher values raise the
bound for both endpoints. This prevents a too-tight client bound from aborting a
request that can still be billed server-side. The runner already sends one
image per request sequentially; batching was never the timeout issue. Walk
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
asset's request identity, prompt, seed, parameters, timestamp, returned cost
meter (`{ "meter": "usd" | "generations", "amount": number }`), source
reference hash (where applicable), and PNG SHA-256 so it can be regenerated and
checked. PixelLab can bill this account in USD or generation credits; credit
pricing depends on the account's plan, so the manifest never invents a USD
conversion.

The runner caps USD spend at $15 and generation credits at 30 across the full
trial. A still request may consume at most 2 generation credits, while the
four-frame animation request may consume at most 8; unexpected or over-cap
usage responses stop the run before another request begins.

PixelLab's animation endpoint requires a 64×64 output, while Bartizan's current
walk-sprite contract is 32×64. The runner therefore requests 64×64 animation
frames and records each decoded PNG's `actualImageSize` in the manifest; the
sprite remains in its intended 32×64 region pending the Mayor's reconciliation
of this asset-contract deviation in the art document.

`assets/trial/` is deliberately committed: its sprites are the product of this
bounded trial, and its manifest is their provenance record.

**Manifest fields (schemaVersion 5):** each asset entry records the request
identity, prompt, seed, params, timestamp, `requestedImageSize` and
`actualImageSize`, PNG `sha256`, and its billing: `cost` (the returned
`{meter, amount}`) for still assets; walk frames instead carry the full
call's `requestCost` plus `amortizedCost` (the per-frame share) — and on a
generation-credit-billed account a walk frame has **no `cost` key at all**,
by design, because a quarter of a credit is not a thing the vendor charges.

Walk entries additionally record `referencePadding` (`{from: 32×64, to:
64×64, placement: "bottom-center"}`): PixelLab requires the animation
reference to match the 64×64 output size, and per the asset contract's
no-resample rule the master's pixels are **padded onto a transparent 64×64
canvas unchanged** — never scaled or resampled — before being sent.
