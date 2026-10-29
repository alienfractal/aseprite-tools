# Hugging Face Reference Variations for Aseprite

Draw one rock, select it, and generate related rocks through your own Hugging Face Space. Each result becomes a frame in a new sprite. The original sprite is never changed.

Windows, Python 3.10+, and Aseprite 1.3.x. Defaults to `lienthealien/Qwen-Image-Edit-2511-LoRAs-Fast`.

Also supports your SDXL Space: `lienthealien/RuinedHugg`.

The companion **HF Animation.lua** tool uses `lienthealien/MiniMax-H3-Turbo-Lora-UNCENSORED` to create short pixel-art animations from Aseprite frames.

## Animate between Aseprite frames

Run **HF Animation** with a sprite open. Its **Mode** menu exposes both frame-pack APIs:

- **Pixel art frames** (`/generate_frames`): use a start frame only and let MiniMax invent the motion, or provide both start and end Aseprite frame numbers. Choose 5 or 7 total output frames.
- **Pixel art timeline** (`/generate_timeline`): provide start and end Aseprite frame numbers, a common style prompt, and a separate transition action. Choose 4, 5, or 7 generated frames between the two exact supplied poses.

Both APIs return a horizontal sprite-sheet PNG plus a ZIP of ordered native-size PNG frames. **Open result as** can import the individual frames, the complete sprite sheet, or both as new RGB Aseprite sprites. Frame durations are set so the frame animation's playback length matches **Model duration**.

If a selection exists and **Use the same selection bounds on both frames** is enabled, keyframes are cropped to that same rectangle. The source sprite remains untouched.

The animation dialog also exposes the Space's `larry`, `lightx`, and `off` turbo-LoRA modes, seed, steps, model canvas, prompt upsampling, and upload background. A seed of `-1` chooses a random seed. Jobs use the same encrypted Hugging Face account profiles and background launcher as HF Variations, while animation preferences are kept separately in `animation-settings.local.json`.

## Mage-VL prompt proposal

Both **HF Variations** and **HF Animation** offer an **Improve prompt with Mage-VL** button. It sends the prepared reference image to `lienthealien/mage-vl-demo` through `/ask_image`. Mage-VL describes the visible subject, pose, composition, pixel-art treatment, palette, lighting, and background. The bridge combines that description with the current prompt and pastes the proposal back into the dialog's prompt field.

This action stops after filling the prompt field: it never submits Qwen, SDXL, or MiniMax. Review or edit the proposed text, then click the normal Generate button only if you want to use it. The dialog exposes the vision Space, description request, and maximum description tokens. The original prompt, Mage-VL description, and exact proposal are also saved in the job's `prompt-details.json`.

## Choose Qwen or SDXL

Use the **Backend** dropdown in Aseprite:

- **Qwen image edit:** `/infer`, Pixel-Art-Refiner, 4 steps, guidance 1. Uses an editing instruction with the reference image.
- **RuinedHugg SDXL:** `/generate`, Juggernaut XL - Ragnarok, 25 steps, guidance 7. The bridge explicitly uses **Image to image**. It never relies on the Space's text-to-image default.

Switching the backend fills in its Space, endpoint, steps, guidance and starter prompt, and shows its relevant settings. Your saved `default` account works with both Spaces. Reopen the script after updating it to see the backend selector.

SDXL exposes **Denoising**, default `0.45`. Lower values generally preserve more of the reference; higher values permit larger changes. For SDXL, describe the desired image in the prompt (for example, "one isolated pixel-art rock, chipped edges, upper-left lighting"), rather than relying only on an editing instruction.

Click **Inspect API** to fill the **SDXL LoRA** dropdown with the choices currently offered by RuinedHugg, such as `pixel-art-xl-v1.1.safetensors` or `PixelArtRedmond-Lite64.safetensors`. `None` is always available and disables that slot. Refreshing keeps your selection if it is still offered; otherwise it selects None. The fetched list is cached locally for the next launch. The tool exposes the first LoRA slot; the other slots use the Space's empty defaults. **LoRA strength** controls that slot. The SDXL style selector sends the separate multiselect style input in the format RuinedHugg expects.

Before requesting a GPU generation, the bridge calls RuinedHugg's CPU preparation endpoint to validate the input and fetch the optional LoRA. If its model is still loading, the Space's error is shown. Canny is disabled. The generation size follows the reference's aspect ratio with the long side at 1024, dimensions rounded to multiples of 64 and limited to 256–1024. References are padded to fit rather than cropped. The existing output-resizing and palette-matching options still apply.

Every variation starts from the same original reference; SDXL does not progressively feed its output back into the next job. Results open as frames in a new sprite just like Qwen results.

## Installation and deployment

This tool is maintained in the aseprite-tools repository. Keep this folder beside
HF Variations Launcher.lua and HF Animation Launcher.lua in Aseprite's Scripts
folder. The launchers resolve this folder relative to themselves.

1. Run Setup.cmd in this folder to create a local Python environment and configure an account.
2. In Aseprite choose File → Scripts → Rescan Scripts Folder.
3. Run either HF launcher with a sprite open. Inspect API checks access without generating images.
4. Choose your settings and click Generate when ready.

Use Deploy-HF.ps1 in the repository root to install or update another Scripts
folder. See the root README for commands. Each installation keeps its own
accounts, preferences and jobs. Recreate the environment with Setup.cmd after
moving it; virtual environments should not be copied between locations.

## Existing Hugging Face login

The `default` profile first uses a locally saved account from **Accounts.cmd**. If there is none, it reuses the token from Hugging Face's normal `HF_TOKEN` environment setting or `hf auth login` credential cache.

**Login.cmd** provides the normal Hugging Face terminal login if you prefer it. That login changes the active Hugging Face account for other tools using the same credential cache. Named profiles in Accounts.cmd let this script choose among accounts without changing that shared login.

Account tokens entered in Accounts.cmd are encrypted with Windows DPAPI for the current Windows user and saved in `accounts.local.json`. They are not written into Lua, job JSON, command lines or image metadata. The account window can delete a profile. Copying an encrypted account file to another Windows user/computer will not make its tokens usable there.

## Rock prompt

The dialog starts with a rock-variation prompt. A shorter alternative:

> Make one new rock from this reference. Change its silhouette, cracks and chipped edges. Keep the same pixel-art style, palette, material, perspective and upper-left lighting. Show one centered, fully visible rock on the same plain background. No text or extra objects.

Each variation uses the original reference, rather than the previous generated result. A seed of `-1` chooses a fresh seed for each image. A fixed seed uses that seed, seed+1, seed+2, etc. Requested seeds and returned seeds when available are recorded in the job results.

## Drawing and output behavior

- Sends the **visible composite of the current frame**. With the selection option enabled, it crops to the selection's bounding rectangle; pixels inside that rectangle are included even if a freehand selection excludes them. Hide unrelated layers before generating.
- Indexed and RGB sources export correctly as an RGB/RGBA reference PNG. The indexed original remains untouched.
- Qwen receives an opaque reference: transparent areas are composited onto **Upload background**, default white (`#ffffff`). Small references can be enlarged with nearest-neighbor before upload.
- **Resize results** uses nearest-neighbor to restore the reference's dimensions. This resizes generated details; it does not guarantee hand-drawn pixel-art quality or identical framing.
- **Match source palette** maps the returned image's RGB colors to the source palette without dithering. Returned alpha is retained. This can help match your game art but may lose subtle model shading.
- Results open in a **new RGB sprite**, one frame per variation. Palette matching restricts the colors while retaining RGB storage. You can export it as a sprite sheet or use the color-reduction script afterward.
- Generated output usually has an opaque background. Background removal is not included, and original transparency is not used as an output mask because a new rock can have a different silhouette.
- Reference images, prompts, downloaded originals and resized PNGs are kept in timestamped subfolders under `jobs/`. Deleting a job folder later removes that local history. Source `.aseprite` documents are not saved or overwritten.

## Compatibility and errors

For Qwen, the bridge calls the cloud Space's `/prepare_request` endpoint before `/infer`, matching the webpage's request sequence. This lets the cloud server cache Civitai-hosted adapters such as Pixel-Art-Refiner before entering the GPU worker. Model and LoRA weights are not downloaded to your PC. If preparation fails, no inference job is submitted. Closing and reopening the launcher restores a valid LoRA if an older saved setting was blank.

The bridge inspects the Space API rather than assuming an argument order. It supports the common `/edit_image`, `/infer`, and `/predict` Qwen endpoints, plus RuinedHugg's `/generate` SDXL endpoint, with either base64-JSON images, a Gallery input, a list of image files, or a single image. It accepts base64 image results, downloaded image files, and image+seed/details results. An endpoint can also be entered explicitly.

Other required API parameters stop the request with an error instead of guessing. The **api-info.json** in the job folder describes the endpoint and can be shared to adapt the script; it does not contain your token. API support is not a guarantee that every Space bearing the Qwen name has the same contract.

Your specific Space's live API was successfully inspected using your locally supplied token. Its `/infer` endpoint accepts the base64 reference, prompt, LoRA, style, seed, randomization flag, guidance, LoRA strength, steps and optional output-resolution setting. The bridge supports those inputs and its image+seed output format. After fixing the preparation sequence, one actual Qwen generation using the reference from a failed user job completed successfully and returned its PNG. Cloud preparation, inference and image download have now been verified end to end.

RuinedHugg's authenticated live API and application source were also inspected. Its generation and model-preparation contracts were validated locally. No SDXL GPU generation was submitted during implementation.

The Space runs on your Hugging Face account's available hardware/quota. This tool does not buy credits, duplicate Spaces or change hardware. Clicking Generate submits the requested number of jobs sequentially. It does not automatically retry failed generations. Cancellation prevents further submissions and requests cancellation of the current queued job; a generation already running on the server may finish. Earlier successful variations are retained and imported if a later request fails.

Aseprite may ask permission to write reference/job files or execute the local helper on first use. Those prompts come from Aseprite's Lua permissions. The helper uses a background Python process so Aseprite remains usable while waiting.

## Verification

Tested the export/import functions in Aseprite 1.3.18.6: indexed colors, selection crop, original-sprite safety, palette extraction, individual animation frames, and full sprite sheets. Twenty-seven offline Python tests cover the two variation backends plus the non-generating Mage-VL prompt-preview flow, MiniMax frame-pack and timeline argument mapping, ordered ZIP-frame import, and sheet output, Qwen cloud-adapter preparation and failure handling, SDXL image-to-image mode, preparation/LoRA slot mapping, style/strength inputs, exact reference reuse, seed progression, resizing, palette matching, cancellation, partial results, token redaction and DPAPI encryption. The background launcher is checked separately. These tests make no paid generation calls.

The Python test command is `.venv\Scripts\python.exe -m unittest test_bridge.py -v` from this folder. The test sources are included in the repository; deployment copies only runtime files.

References: [Gradio client](https://www.gradio.app/main/docs/python-client/introduction), [public Qwen upstream source](https://huggingface.co/spaces/prithivMLmods/Qwen-Image-Edit-2511-LoRAs-Fast/blob/main/app.py), [Aseprite scripting API](https://www.aseprite.org/api/).
