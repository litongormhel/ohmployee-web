/**
 * Client-side image compression for HR Emploc document uploads.
 * Supported: image/jpeg, image/png, image/webp.
 * - Max dimension: 1600px (width or height)
 * - Quality: 0.75
 * - No upscale if original image is smaller than 1600px
 * - If compressed file is larger than the original, returns the original
 * - PDFs and other non-image MIME types pass through untouched.
 */

export interface CompressionOptions {
  maxDimension?: number;
  quality?: number;
}

export async function compressDocumentFile(
  file: File,
  options: CompressionOptions = {}
): Promise<File> {
  const { maxDimension = 1600, quality = 0.75 } = options;

  // Only compress JPEG, PNG, WEBP
  const isImage = ["image/jpeg", "image/png", "image/webp"].includes(file.type);
  if (!isImage) {
    return file;
  }

  // If in SSR or canvas not available, return original
  if (typeof window === "undefined" || !window.createImageBitmap) {
    return file;
  }

  try {
    const bitmap = await createImageBitmap(file);
    let { width, height } = bitmap;

    // Do not upscale; only scale down if larger than maxDimension
    if (width > maxDimension || height > maxDimension) {
      if (width >= height) {
        height = Math.round((height * maxDimension) / width);
        width = maxDimension;
      } else {
        width = Math.round((width * maxDimension) / height);
        height = maxDimension;
      }
    } else {
      // Image is already within dimensions
      // If original file is already reasonable size (< 500KB), keep original
      if (file.size < 500 * 1024 && file.type !== "image/png") {
        bitmap.close();
        return file;
      }
    }

    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      bitmap.close();
      return file;
    }

    ctx.drawImage(bitmap, 0, 0, width, height);
    bitmap.close();

    const targetMime = file.type === "image/png" ? "image/jpeg" : file.type;
    const blob: Blob | null = await new Promise((resolve) => {
      canvas.toBlob(resolve, targetMime, quality);
    });

    if (!blob || blob.size >= file.size) {
      // Fallback to original if compression didn't reduce file size
      return file;
    }

    const newFileName =
      file.type === "image/png"
        ? file.name.replace(/\.png$/i, ".jpg")
        : file.name;

    return new File([blob], newFileName, {
      type: targetMime,
      lastModified: Date.now(),
    });
  } catch (err) {
    console.warn("Client image compression failed; using original file:", err);
    return file;
  }
}
