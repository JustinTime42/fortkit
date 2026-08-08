# Bartizan art pipeline — research and decision proposal

**Status:** proposal only; prepared for `fortkit-1np` on 2026-08-07. It does
not authorize an account, purchase, download, model installation, or renderer
change. The Mayor's later sprite-integration bead owns the adopted style guide
and the L1/L4 layout freeze.

## Decision

Choose **local-first ComfyUI with a project-owned adapter trained only on
approved material over an authorized SDXL 1.0 base** as the production path.
Its marginal generation cost is $0 on the Overseer's already-owned GPU; it
keeps prompt/reference assets private; and a frozen workflow, seed, reference
sheet, palette, and post-processing script make a whole set more repeatable
than prompt-only cloud generation. Pixel Art XL is a named trial candidate,
not the default: it remains ineligible until its complete license record and
training-data provenance are recorded and approved.

This is not a claim that any arbitrary SDXL checkpoint or community LoRA is
cleared for release. Before use, the Overseer must approve the exact revision,
weight hash, upstream licenses, and training-data provenance. Use only models
whose terms permit the intended distribution and retain a per-asset provenance
record. ComfyUI itself is GPL-3.0, so keep it as an internal generation tool;
do not embed or distribute modified ComfyUI code with Bartizan without a
license review.

## Concrete weight candidates and license record

Research retrieved **2026-08-07** from the public pages linked below. These
are candidates for an Overseer authorization, not permission to download,
accept a click-through, or use a weight. A released art asset is an *output*;
it is not a redistribution of the weights. Distributing a checkpoint, LoRA,
or a fine-tune is a separate event and triggers the distribution duties below.
The authorization record must pin the repository revision and SHA-256 of every
file actually used; a moving `main` label is insufficient.

| Candidate | Public license record (quoted text) | Consequence for Bartizan distribution | Decision |
| --- | --- | --- | --- |
| [`stabilityai/stable-diffusion-xl-base-1.0`](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0) checkpoint | The public `LICENSE.md` is **CreativeML Open RAIL++-M**. It grants a “perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable copyright license” and says that the licensor “claims no rights in the Output” (subject to the license). A distributor of the model/derivative must give recipients a copy of the license and carry its use restrictions forward. | Generated PNGs may be shipped only after the project checks the actual output and intended use against the license and other applicable rights. If Manyhalls ever ships the base, a derivative, or a fine-tune, it must include the license, notices, and enforceable use restrictions; do not bundle weights with Bartizan. | **Eligible base**, subject to a pinned hash and provenance approval. |
| [`nerijs/pixel-art-xl`](https://huggingface.co/nerijs/pixel-art-xl) LoRA | The public model page identifies it as a LoRA for the SDXL 1.0 base and labels its license **CreativeML OpenRAIL-M**. The public repository page supplies no license-text file or training-data/provenance statement to verify the claimed distribution terms; only the license identifier is publicly reachable. | A license tag alone is not sufficient evidence to redistribute this LoRA or a derivative. Do not ship it, a merge, or a fine-tune. Outputs also remain subject to the SDXL base terms and any third-party rights. | **Conditional trial candidate only**: the Overseer must obtain and record the complete license text and provenance before download/use; otherwise train a project-owned adapter on approved material. |
| [`black-forest-labs/FLUX.1-dev`](https://huggingface.co/black-forest-labs/FLUX.1-dev) checkpoint | Black Forest Labs' ungated, canonical [`model_licenses/LICENSE-FLUX1-dev`](https://github.com/black-forest-labs/flux/blob/main/model_licenses/LICENSE-FLUX1-dev) states **FLUX.1 [dev] Non-Commercial License v1.1.1**. It grants model/derivative rights “solely for your Non-Commercial Purposes” and defines revenue-generating activity and end-user-impacting use as not non-commercial. It says outputs are not derivatives and that BFL claims no ownership in outputs; model/derivative distribution must carry the license and attribution notice. | A public Bartizan product is an end-user-facing use, so its production generation pipeline cannot rely on these dev weights without a separate commercial license. Output wording does not cure the model-use restriction. | **Not eligible for the production path**; retain only as a reference-only option pending separate commercial authorization. |

The SDXL base license text is public at both the [model repository](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/blob/main/LICENSE.md) and [Stability AI's source repository](https://github.com/Stability-AI/generative-models/blob/main/model_licenses/LICENSE-SDXL1.0). The Pixel Art XL page's incomplete public record is itself a finding, not an invitation to create an account or accept terms. The FLUX model page is publicly readable but its files are gated; the FLUX license characterization above was read from Black Forest Labs' ungated public GitHub license file, not from the gated model repository. No account, sign-up, download, or click-through occurred for this research.

**Managed fallback: PixelLab API.** It directly supports text-to-pixel-art,
reference/style images, forced palettes, and transparent backgrounds, at about
$0.007–$0.013 per image for the relevant sizes. It is the practical choice if
the local GPU cannot produce accepted candidates after the controlled trial or
if its setup cost exceeds the small initial set. It requires an account, API
credential, and acceptance of PixelLab's then-current terms—each a Human Gate
3 action.

**Escalation, not default: Scenario.** Its custom model training is attractive
for a large continuing asset program, but API access needs a paid Pro-or-higher
plan ($45/month) and training consumes approximately 100–500 compute units.
Use it only after enough approved reference art exists to justify style-model
training. Its paid plans say the output is commercially usable; verify that
claim and current terms at purchase time.

**Reference-only frontier option: BFL FLUX API.** FLUX.2 Pro is advertised from
$0.03 per image and FLUX.1.1 Pro at $0.04. It may make strong concept sheets
or paintovers, but it is not the chosen final-pixel generator: rendering
low-resolution sprites by downsampling a general image generator causes
silhouette and palette drift. The API additionally needs an account, credits,
and an API key.

**Do not select Retro Diffusion without a live vendor check.** Fresh searches
did not yield a current official API/pricing/terms page sufficient to support
a procurement decision. The Overseer may reopen it only when an official URL
states availability, price, API contract, output rights, retention, and
relevant pixel-art controls.

## Cost comparison (research snapshot, 2026-08-07)

The counts below are planning estimates, not vendor quotes. A candidate budget
of 12 generations per approved final (then one retained output) puts the
direct generation cost at roughly:

| Path | Published price / fixed cost | Cost for 12 candidates | Suitability |
| --- | ---: | ---: | --- |
| Local ComfyUI + approved local weights | $0 marginal; GPU/electricity already owned | $0 marginal | Recommended: private, workflow/seed locked |
| PixelLab Pixen 64×64 | $0.00718/image | $0.086/final | Managed fallback; native pixel art |
| PixelLab Pixflux 64×64 transparent | $0.00840/image | $0.101/final | When alpha is needed at generation |
| PixelLab Bitforge 128×128 | $0.00797/image | $0.096/final | Reference/style and palette controls |
| BFL FLUX.2 Pro | from $0.03/image | from $0.36/final | Concepts/reference sheets |
| Scenario Pro | $45/month, 5,000 CU | CU varies; 2–15 CU/image | Only after custom-style scale is proven |

At this rate, a first set of 12 building masters, 4 citizen masters, 8 item
glyphs, and 4 walk-cycle masters (28 accepted assets; 336 candidates) would
be about $2.41 in PixelLab Pixen generation or $10.08 at BFL's stated FLUX.2
Pro floor, before human selection/rework. Animation frames are *not* assumed
to be independent generations: derive them from a selected citizen master and
validate frame-by-frame to prevent identity drift.

## What the trial must prove

No live samples were generated: the dispatch forbids account creation, sign-up,
or purchase, and this worktree has no approved image-generation credential.
The following reproducible **sample card** is the decision-quality substitute
until the Overseer authorizes a bounded trial. It turns taste into a visible
selection loop without pretending a deterministic verifier can judge beauty.

| Field | Required recorded value |
| --- | --- |
| Subject | `forge-building`, `kethra-citizen`, `implementation-crate`, or `walk-east-02` |
| Prompt | “orthographic 3/4 exterior, humble dwarven stone forge, 32-bit pixel art, single object, no text, no logo” (subject-specific prefix allowed) |
| Negative constraints | no words, UI, watermark, photorealism, isometric grid, extra people |
| Canonical reference | approved contact sheet and prior accepted master, content-hashed |
| Locked inputs | generator/model/weight hash, workflow hash, seed, resolution, prompt, reference hash |
| Output gates | palette, dimensions, alpha, tile-grid/sheet checks pass |
| Human result | Overseer: accept / reject, short reason, chosen output hash |

Run 12 candidates for one forge, one citizen, one glyph, and one four-frame
walk cycle through the same declared palette. Review the contact sheet at
100%, 400%, and at the actual canvas scale. The trial passes only if the
Overseer accepts at least one usable candidate in each category *and* can tell
the citizen's four frames are the same actor. Otherwise try the managed
fallback before paying for Scenario training.

### Trial-run provenance costs

The bounded PixelLab runner writes a schema-version-4 provenance manifest.
Each asset's `requestCost` records the complete meter returned for the API call.
For a four-frame animation, a divisible USD `cost` is the per-frame share;
generation credits are instead recorded as `amortizedCost` so a fractional
allocation is never presented as a separately charged generation.

## Consistency rules

1. A Mayor-authored per-fort style guide owns palette, camera angle, outline
   treatment, material vocabulary, accessibility contrast, and prohibitions;
   this proposal deliberately does not choose those aesthetic values.
2. Generate a canonical contact sheet first: buildings, citizens, items, and
   a four-direction pose strip. Every later request includes it as a reference
   and records its hash.
3. Pin generator version, weight hashes, workflow JSON hash, seed, prompt, and
   reference hash in an asset manifest. New versions are new experiments, not
   silent replacements.
4. Use image-to-image/character reference for variants; use independent
   generation only for deliberately distinct actors. Assign exactly one
   selected actor master to each named actor; animation and directional variants
   derive from that master. The renderer's current name-sorted styling is not
   an art identity system, so later L4 must map stable roster identity to its
   selected actor master.
5. Palette quantization happens once, after alpha cleanup and before packing.
   Never quantize a completed sheet a second time; it can alter transparent
   edge pixels and introduce seams.
6. A building master preserves transparent pixels and derives its occupied
   world footprint from its layout placement and declared frame, never from a
   painted opaque bounding box. Its art may not silently change the building's
   fixed layout footprint.
7. Provide N/S/E/W directional variants. Mirror a direction only when the
   adopted style guide explicitly permits that mirror for the relevant asset;
   otherwise each direction is a distinct approved frame.
8. Provide exactly one item glyph for every declared work type. A newly
   declared work type is incomplete until its glyph is added to the manifest;
   do not reuse a glyph to stand in for another declared type.

## Proposed asset contract for the later integration bead

The `1100×620` canvas element belongs to `src/colony-page.html` (not
`src/colony-page.ts`); the page script can later change its runtime height.
The current 210×112 placeholder-building rectangles are UI values, not an
art contract. Do not crop art to either value. Freeze world coordinates and
zoom behavior in fci L1/L4 first, then use this single grid rule.

**A native art cell is exactly 32×32 master pixels, and one native art pixel
equals one CSS/world pixel at zoom 1.** A master is the canonical, native pixel
grid; a runtime cell is a world-unit measure at zoom 1, not a smaller image.
The renderer **must never resample a master with any filter**. It may place a
master at native size or apply a positive integer nearest-neighbor upscale;
integer nearest-neighbor scaling is the sole allowed resampling exception.
It must never use a non-integer ratio or any downscale. The asset verifier must
reject any manifest scale ratio other than 1 or a positive integer, and the
renderer must set `imageSmoothingEnabled = false`.

| Asset | Canonical master/frame | Zoom-1 world footprint | Sheet rule |
| --- | ---: | ---: | --- |
| Building | 128×128 PNG with meaningful transparent background | 4×4 cells (128×128 world px), from the fixed layout placement | origin and dimensions are multiples of 32; opaque pixels do not redefine the layout footprint |
| Citizen | 32×48 visible pixels in a 32×64 transparent frame | 1×2 cells (32×64 world px) | frame slot is grid-aligned; baseline is the frame bottom |
| Walk cycle | 4 × 32×48 visible pixels, each in a 32×64 frame | 1×2 cells per frame | each frame slot is grid-aligned |
| Item glyph | 32×32 PNG | 1×1 cell | origin and dimensions are multiples of 32 |
| Sheet | exactly 512×512 PNG | 16×16 native cells | JSON frame atlas; no implicit spacing |

Thus 192×128 masters and alternate 64/96 logical runtime cells are not part of
this contract. A 512×512 sheet is exactly a 16×16 grid, so every frame origin
and allocated frame rectangle divides it cleanly. The 16-pixel transparent
padding above a citizen's 48-pixel visible art is intentional and must be
preserved, not cropped or rescaled. Alpha is meaningful only as fully
transparent (0) or fully opaque (255) for this first style: reject
semi-transparent pixels, which otherwise produce fringe colors against any
fort background.

### Multi-sheet allocation

`sheet-001` is the first 512×512 (16×16-cell) atlas. Allocate a release set's
declared assets in stable manifest-ID order, row-major, with each frame or
frame group occupying one contiguous grid-aligned rectangle and never crossing
a sheet boundary. The planned first set uses 240 of 256 cells: twelve 4×4
building masters (192), four 1×2 citizen masters (8), eight 1×1 glyphs (8), and
four four-frame walk cycles (32). Its remaining 16 cells are ordinary capacity,
not permission to repack existing art.

When the active sheet has no empty contiguous rectangle large enough for the
next declared asset or frame group, create the next numbered 512×512 sheet and
continue there. Fragmented free cells do not justify moving an existing frame;
published atlas placements are immutable, and an asset's frames must stay on
its declared sheet. The manifest records the sheet ID and rectangle for every
frame, so allocation remains deterministic and auditable.

## Deterministic Warden gate (design for a follow-up implementation bead)

The generator never becomes a source of truth. A deterministic verifier should
consume a manifest and PNG files and fail with file/pixel coordinates. It must
check these mechanical claims; Overseer review remains the taste gate:

| Check | Pass condition |
| --- | --- |
| Manifest | schema-valid; every declared frame resolves inside its sheet; no overlap; names unique |
| PNG dimensions | exact master/frame dimensions and sheet dimensions allowed by manifest |
| Palette | every non-transparent RGBA pixel exactly equals a declared palette color |
| Alpha | alpha is exactly 0 or 255; RGB for alpha 0 is canonicalized to `0,0,0` |
| Tile/grid | x/y/w/h are positive integers, inside sheet bounds, and multiples of the fixed 32-pixel cell |
| Sheet validity | frame rectangles do not overlap; no unreferenced nontransparent pixel outside declared frames (optional strict mode) |
| Scaling | source and target scale are positive integer ratios; no smoothing policy violation |
| Provenance | manifest captures source/output hashes and pinned workflow inputs; missing values warn in exploration, fail for release |

The implementation may use a maintained image decoder, but calculations must
be local and deterministic; no model/API call is allowed during verification.
Include adversarial fixtures: off-palette one-pixel error, alpha 127, frame
out of bounds, frame overlap, bad alignment, and wrong dimensions.

## Human authorization needed before any trial

1. Approve the model/LoRA/license/provenance manifest and any model download;
   confirm the GPU host and storage location are in scope.
2. If local generation is unavailable, create the selected vendor account,
   accept terms, fund it, and place its credential in the approved secret
   boundary. The Limner must never expose a key in prompts, events, commits,
   manifests, or screenshots.
3. Approve the bounded spend/candidate budget and whether generated outputs
   may leave the local machine for a cloud vendor.
4. Review the contact sheet visually and select final outputs. This is not
   delegable to a palette verifier.

## Proposed LIMNER charter amendment (draft only)

This is intentionally a **draft amendment**, not a modification to `fort/`.
It is for Warden + Overseer review under Human Gate 1.

> **Seat: Limner** — The Limner produces and curates visual assets from an
> approved style guide and asset manifest. Its office begins only when the
> first asset-generation bead is ready to claim (Bartizan colony assets or
> Longburn T1). The Limner's inner loop is multimodal and mandatory: generate
> or transform → inspect the actual output at native and intended runtime
> scale → compare against the approved reference/contact sheet → record
> acceptance or rejection → iterate. A text-only account of an image is not
> inspection. The seat's ladder must retain image-viewing capability at every
> rung; if it cannot see its output, it stops and escalates rather than
> approving unseen art.
>
> The Limner may write only generated assets, manifests, and approved
> art-pipeline artifacts in its isolated worktree. It never changes product
> behavior, renderer code, charter, seat profiles, or secret files; later
> integration remains Forge work. It commits path-scoped and submits the
> deterministic art-verifier result plus the contact sheet/manifest for Warden
> review. The Warden checks reproducible mechanical constraints, provenance,
> and scope; the Overseer alone accepts visual taste and style conformance.
>
> **Image-generation credentials are a gated permission class.** They are
> Human Gate 3 credentials: a human creates the account, approves vendor/model
> terms and spend, installs the secret outside agent-readable paths, and may
> revoke it. A Limner receives only the narrow invocation capability needed for
> the approved provider/workflow, never raw credential read access. The event
> stream may record provider/model/request identity and non-secret cost
> metadata, never prompts containing private references, raw request payloads,
> tokens, signed URLs, or credentials. Local model downloads likewise require
> an explicit approved source and license record.

## Sources (freshly checked 2026-08-07)

- [PixelLab API models, controls, and estimated per-image prices](https://www.pixellab.ai/pixellab-api)
- [PixelLab Terms of Service](https://www.pixellab.ai/termsofservice)
- [Scenario pricing, custom-training requirements, privacy, and commercial-output statement](https://www.scenario.com/pricing)
- [Scenario API compute-unit usage and dry-run support (updated 2026-04-09)](https://help.scenario.com/articles/7934059476-api-usage-and-credits-compute-units)
- [Scenario API access requirements](https://www.scenario.com/features/api)
- [Black Forest Labs current API pricing](https://docs.bfl.ai/quick_start/pricing)
- [Black Forest Labs release notes on fixed versus preview endpoints](https://docs.bfl.ai/release-notes)
- [ComfyUI repository and GPL-3.0 license](https://github.com/Comfy-Org/ComfyUI)
- [SDXL 1.0 base `LICENSE.md` (CreativeML Open RAIL++-M)](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/blob/main/LICENSE.md)
- [Pixel Art XL public model page (CreativeML OpenRAIL-M label; no public full license/provenance text)](https://huggingface.co/nerijs/pixel-art-xl)
- [Black Forest Labs' ungated FLUX.1 [dev] license (Non-Commercial License v1.1.1)](https://github.com/black-forest-labs/flux/blob/main/model_licenses/LICENSE-FLUX1-dev)

Vendor pricing, limits, availability, and terms change. Recheck these primary
sources immediately before authorization or procurement.

---

**Correction (appended by the Mayor, 2026-08-08, per Warden 00h finding 7 and standing order 7):**
the "PixelLab Pixen 64×64" model named in the cost table above, and the ~$2.41
project estimate derived from its $0.00718/image price, reference a model name
that does not exist in PixelLab's API. The verified endpoints (per
`https://api.pixellab.ai/v1/openapi.json`, checked 2026-08-08 after a live 422)
are `generate-image-pixflux`, `generate-image-bitforge`, `animate-with-text`,
and `animate-with-skeleton`. Treat the Pixen rows as superseded; live per-asset
costs are now observed directly in `assets/trial/provenance-manifest.json`
(`usage.usd`) and are the figures to budget from. The original text stands
unedited above as the record of what the research believed.
