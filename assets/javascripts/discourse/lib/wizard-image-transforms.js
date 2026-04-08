import loadScript from "discourse/lib/load-script";

// Lazy-loaders for client-side image processing libraries. Both load from
// jsdelivr on first use so the ~400KB HEIC library and ~40KB compression
// library never enter the initial bundle — they only land on wizards that
// actually enable these options.
//
// NOTE: admins using a strict Content-Security-Policy must allowlist
// `cdn.jsdelivr.net` under `script-src`, or compression / HEIC conversion
// will silently fall back to uploading the original file.

const IMAGE_COMPRESSION_URL =
  "https://cdn.jsdelivr.net/npm/browser-image-compression@2.0.2/dist/browser-image-compression.js";
const HEIC2ANY_URL =
  "https://cdn.jsdelivr.net/npm/heic2any@0.0.4/dist/heic2any.min.js";

let imageCompressionPromise;
let heic2anyPromise;

// Cache successful loads so repeated uploads on the same page reuse the
// already-fetched script, but clear the cache on failure so transient
// errors (network blip, temporary CSP block, CDN outage) don't
// permanently poison the transform pipeline for the rest of the session.
function loadImageCompression() {
  if (!imageCompressionPromise) {
    imageCompressionPromise = loadScript(IMAGE_COMPRESSION_URL)
      .then(() => window.imageCompression)
      .catch((e) => {
        imageCompressionPromise = null;
        throw e;
      });
  }
  return imageCompressionPromise;
}

function loadHeic2Any() {
  if (!heic2anyPromise) {
    heic2anyPromise = loadScript(HEIC2ANY_URL)
      .then(() => window.heic2any)
      .catch((e) => {
        heic2anyPromise = null;
        throw e;
      });
  }
  return heic2anyPromise;
}

function isHeicFile(file) {
  if (!file) {
    return false;
  }
  return (
    /\.heic$|\.heif$/i.test(file.name || "") ||
    file.type === "image/heic" ||
    file.type === "image/heif"
  );
}

function isImageFile(file) {
  return !!file?.type && file.type.startsWith("image/");
}

// Replaces .heic / .heif extensions with .jpg. Preserves the rest of the
// filename including any dots. If no heic extension is found the original
// name is returned unchanged.
function swapHeicExtension(name) {
  return name.replace(/\.hei[cf]$/i, ".jpg");
}

// Apply per-field transforms in-place: HEIC conversion first (so the
// resulting JPEG can also be compressed), then optional compression /
// resizing. Each transform is a best-effort — if a library fails to load or
// throws during processing, the original file is returned so the upload can
// still proceed.
//
// `onStage` is called with one of: "converting", "compressing" so the UI
// can show a progress label while the async work runs.
export async function transformFileForUpload(file, options = {}, onStage) {
  let result = file;

  if (options.convertHeic && isHeicFile(result)) {
    onStage?.("converting");
    try {
      const heic2any = await loadHeic2Any();
      const blob = await heic2any({
        blob: result,
        toType: "image/jpeg",
        quality: 0.92,
      });
      const converted = Array.isArray(blob) ? blob[0] : blob;
      result = new File([converted], swapHeicExtension(result.name), {
        type: "image/jpeg",
        lastModified: Date.now(),
      });
    } catch (e) {
      // Conversion failed — log and fall through to the original file so the
      // upload can still proceed. Discourse will either accept the HEIC
      // (rare) or surface the standard upload error.
      // eslint-disable-next-line no-console
      console.warn("wizard: heic conversion failed", e);
    }
  }

  if (options.compressImages && isImageFile(result)) {
    onStage?.("compressing");
    try {
      const imageCompression = await loadImageCompression();
      const compressionOptions = { useWebWorker: true };
      if (options.maxUploadSizeKb) {
        // browser-image-compression uses MB, we store KB.
        compressionOptions.maxSizeMB = options.maxUploadSizeKb / 1024;
      }
      if (options.maxImageDimension) {
        compressionOptions.maxWidthOrHeight = options.maxImageDimension;
      }
      const compressed = await imageCompression(result, compressionOptions);
      // `imageCompression` returns a Blob, not a File. Wrap it back so the
      // filename survives to the server.
      result = new File([compressed], result.name, {
        type: compressed.type || result.type,
        lastModified: Date.now(),
      });
    } catch (e) {
      // eslint-disable-next-line no-console
      console.warn("wizard: image compression failed", e);
    }
  }

  return result;
}

// Pure client-side size check used to reject files that exceed the cap
// BEFORE we try to transform or upload them. Returns `{ ok, maxKb,
// actualKb }`. A missing / zero `maxUploadSizeKb` disables the check.
export function checkUploadSize(file, maxUploadSizeKb) {
  const maxKb = Number(maxUploadSizeKb) || 0;
  if (maxKb <= 0) {
    return { ok: true };
  }
  const actualKb = Math.ceil((file?.size || 0) / 1024);
  return {
    ok: actualKb <= maxKb,
    maxKb,
    actualKb,
  };
}
