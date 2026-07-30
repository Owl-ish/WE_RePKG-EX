use std::io::Read;
use std::path::Path;
use std::sync::Arc;

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}

#[flutter_rust_bridge::frb]
pub async fn delete_to_trash(file_path: String) -> Option<String> {
    trash::delete(&file_path).map_err(|e| e.to_string()).err()
}

#[flutter_rust_bridge::frb]
pub async fn delete_all_to_trash(file_paths: Vec<String>) -> Option<String> {
    trash::delete_all(&file_paths)
        .map_err(|e| e.to_string())
        .err()
}

/// What a PNG's header alone proves about transparency.
#[derive(Debug, PartialEq, Eq)]
enum AlphaHint {
    /// No alpha channel and no tRNS chunk. The image is opaque; skip the decode.
    Opaque,
    /// Alpha may be present. The pixels have to be examined.
    NeedsDecode,
}

const PNG_SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];

/// Enough bytes to cover the signature, IHDR, and the ancillary chunks that
/// precede the first IDAT. A palette plus tRNS fits comfortably; anything that
/// does not falls back to the full decode.
const HEADER_SCAN_BYTES: usize = 64 * 1024;

/// Decides from the header whether a decode is needed at all.
///
/// Colour type 0 (grayscale) and 2 (truecolour) have no alpha channel, and type
/// 3 (indexed) carries alpha only through a tRNS chunk. For those three, the
/// absence of tRNS proves opacity, answering the question from a few dozen bytes
/// rather than decoding the whole image. Types 4 and 6 have a real alpha
/// channel, so their pixels must be read.
///
/// Anything unrecognised, truncated, or ambiguous returns NeedsDecode. Being
/// wrong in that direction only costs time; the opposite would silently skip
/// files the user asked to delete.
fn alpha_hint_from_header(bytes: &[u8]) -> AlphaHint {
    // 8 signature + 4 length + 4 "IHDR" + 4 width + 4 height + 1 bit depth,
    // which puts the colour type at index 25.
    if bytes.len() < 26 || bytes[..8] != PNG_SIGNATURE || &bytes[12..16] != b"IHDR" {
        return AlphaHint::NeedsDecode;
    }
    let colour_type = bytes[25];
    if !matches!(colour_type, 0 | 2 | 3) {
        return AlphaHint::NeedsDecode;
    }

    // Walk chunk headers looking for tRNS. The spec puts tRNS before the first
    // IDAT, so the scan stops there and never touches compressed pixel data.
    let mut offset = 8usize;
    while offset + 8 <= bytes.len() {
        let length = u32::from_be_bytes([
            bytes[offset],
            bytes[offset + 1],
            bytes[offset + 2],
            bytes[offset + 3],
        ]) as usize;
        match &bytes[offset + 4..offset + 8] {
            b"tRNS" => return AlphaHint::NeedsDecode,
            b"IDAT" | b"IEND" => return AlphaHint::Opaque,
            _ => {}
        }
        // 4 length + 4 type + payload + 4 CRC
        offset = match offset.checked_add(length).and_then(|o| o.checked_add(12)) {
            Some(next) => next,
            None => return AlphaHint::NeedsDecode,
        };
    }
    // Ran past the buffer before reaching IDAT, so opacity is unproven.
    AlphaHint::NeedsDecode
}

fn read_prefix(path: &Path, max: usize) -> std::io::Result<Vec<u8>> {
    let file = std::fs::File::open(path)?;
    let mut buffer = Vec::new();
    file.take(max as u64).read_to_end(&mut buffer)?;
    Ok(buffer)
}

/// Blocking transparency check: header fast path first, full decode only when
/// the header cannot settle it.
fn has_png_transparency_blocking(file_path: &str) -> Result<bool, String> {
    let path = Path::new(file_path);
    // Case-insensitive: a ".PNG" used to fall through as "not a png" and report
    // opaque regardless of its contents.
    let is_png = path
        .extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("png"));
    if !is_png {
        return Ok(false);
    }

    if let Ok(prefix) = read_prefix(path, HEADER_SCAN_BYTES) {
        if alpha_hint_from_header(&prefix) == AlphaHint::Opaque {
            return Ok(false);
        }
    }

    let img = image::open(path).map_err(|e| format!("Failed to open image: {}", e))?;
    // LumaA (colour type 4) was missing here, so a transparent grayscale PNG
    // reported opaque and survived the cleanup.
    Ok(match img {
        image::DynamicImage::ImageRgba8(img) => img.pixels().any(|p| p.0[3] < u8::MAX),
        image::DynamicImage::ImageRgba16(img) => img.pixels().any(|p| p.0[3] < u16::MAX),
        image::DynamicImage::ImageLumaA8(img) => img.pixels().any(|p| p.0[1] < u8::MAX),
        image::DynamicImage::ImageLumaA16(img) => img.pixels().any(|p| p.0[1] < u16::MAX),
        _ => false, // 非RGBA格式没有透明度通道
    })
}

#[flutter_rust_bridge::frb]
pub async fn has_png_transparency_rust(file_path: String) -> Result<bool, String> {
    // Decoding is blocking CPU work. Running it directly on an async worker
    // starved the runtime once a batch was in flight.
    tokio::task::spawn_blocking(move || has_png_transparency_blocking(&file_path))
        .await
        .map_err(|e| format!("Task execution error: {}", e))?
}

#[flutter_rust_bridge::frb]
pub async fn delete_transparent_pngs_rust(file_paths: Vec<String>) -> Vec<String> {
    use tokio::sync::Semaphore;
    use tokio::task::JoinSet;

    // Bound the concurrent decodes. A 4K RGBA decode holds tens of megabytes,
    // and the previous version spawned one task per file, so a large batch could
    // hold every one of those buffers at the same time.
    let permits = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4);
    let semaphore = Arc::new(Semaphore::new(permits));
    let mut tasks = JoinSet::new();

    for file_path in file_paths {
        let semaphore = Arc::clone(&semaphore);
        tasks.spawn(async move {
            let _permit = match semaphore.acquire_owned().await {
                Ok(permit) => permit,
                Err(e) => return Some(format!("Semaphore closed: {}", e)),
            };
            match has_png_transparency_rust(file_path.clone()).await {
                Ok(true) => trash::delete(&file_path)
                    .err()
                    .map(|e| format!("Failed to delete transparent PNG: {}", e)),
                Ok(false) => None,
                Err(e) => Some(format!("Transparency check failed: {}", e)),
            }
        });
    }

    // Errors come back as task return values, which drops the Arc<Mutex<Vec>>
    // the previous version threaded through every task.
    let mut errors = Vec::new();
    while let Some(joined) = tasks.join_next().await {
        match joined {
            Ok(Some(err)) => errors.push(err),
            Ok(None) => {}
            Err(e) => errors.push(format!("Task execution error: {}", e)),
        }
    }
    errors
}

#[cfg(test)]
mod tests {
    use super::*;
    use png::{BitDepth, ColorType, Encoder};
    use std::io::Write;

    /// Writes a PNG with an explicit colour type, optionally carrying tRNS.
    fn write_png(
        path: &Path,
        colour: ColorType,
        data: &[u8],
        width: u32,
        height: u32,
        palette: Option<Vec<u8>>,
        trns: Option<Vec<u8>>,
    ) {
        let file = std::fs::File::create(path).unwrap();
        let mut encoder = Encoder::new(file, width, height);
        encoder.set_color(colour);
        encoder.set_depth(BitDepth::Eight);
        if let Some(palette) = palette {
            encoder.set_palette(palette);
        }
        if let Some(trns) = trns {
            encoder.set_trns(trns);
        }
        let mut writer = encoder.write_header().unwrap();
        writer.write_image_data(data).unwrap();
        writer.finish().unwrap();
    }

    fn tmp_dir() -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "we_repkg_png_{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn hint_of(path: &Path) -> AlphaHint {
        alpha_hint_from_header(&read_prefix(path, HEADER_SCAN_BYTES).unwrap())
    }

    #[test]
    fn grayscale_without_trns_skips_the_decode() {
        let dir = tmp_dir();
        let path = dir.join("gray.png");
        write_png(
            &path,
            ColorType::Grayscale,
            &[0, 128, 255, 64],
            2,
            2,
            None,
            None,
        );
        assert_eq!(hint_of(&path), AlphaHint::Opaque);
        assert_eq!(
            has_png_transparency_blocking(path.to_str().unwrap()),
            Ok(false)
        );
    }

    #[test]
    fn truecolour_without_trns_skips_the_decode() {
        let dir = tmp_dir();
        let path = dir.join("rgb.png");
        let pixels = [255u8, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
        write_png(&path, ColorType::Rgb, &pixels, 2, 2, None, None);
        assert_eq!(hint_of(&path), AlphaHint::Opaque);
        assert_eq!(
            has_png_transparency_blocking(path.to_str().unwrap()),
            Ok(false)
        );
    }

    #[test]
    fn indexed_without_trns_skips_the_decode() {
        let dir = tmp_dir();
        let path = dir.join("pal.png");
        let palette = vec![255, 0, 0, 0, 255, 0];
        write_png(
            &path,
            ColorType::Indexed,
            &[0, 1, 1, 0],
            2,
            2,
            Some(palette),
            None,
        );
        assert_eq!(hint_of(&path), AlphaHint::Opaque);
        assert_eq!(
            has_png_transparency_blocking(path.to_str().unwrap()),
            Ok(false)
        );
    }

    /// palette alpha lives in tRNS, not the colour type byte.
    /// Answering from the colour type alone would call this opaque and leave the
    /// file on disk.
    #[test]
    fn indexed_with_trns_falls_through_and_detects_transparency() {
        let dir = tmp_dir();
        let path = dir.join("pal_trns.png");
        let palette = vec![255, 0, 0, 0, 255, 0];
        write_png(
            &path,
            ColorType::Indexed,
            &[0, 1, 1, 0],
            2,
            2,
            Some(palette),
            Some(vec![0, 255]), // palette entry 0 is fully transparent
        );
        assert_eq!(hint_of(&path), AlphaHint::NeedsDecode);
        assert_eq!(
            has_png_transparency_blocking(path.to_str().unwrap()),
            Ok(true)
        );
    }

    #[test]
    fn truecolour_with_trns_falls_through() {
        let dir = tmp_dir();
        let path = dir.join("rgb_trns.png");
        let pixels = [255u8, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
        write_png(
            &path,
            ColorType::Rgb,
            &pixels,
            2,
            2,
            None,
            Some(vec![0, 255, 0, 0, 0, 0]), // pure red reads as transparent
        );
        assert_eq!(hint_of(&path), AlphaHint::NeedsDecode);
        assert_eq!(
            has_png_transparency_blocking(path.to_str().unwrap()),
            Ok(true)
        );
    }

    #[test]
    fn rgba_needs_a_decode_and_reports_opaque_when_fully_opaque() {
        let dir = tmp_dir();
        let path = dir.join("rgba_opaque.png");
        let pixels = [255u8, 0, 0, 255, 0, 255, 0, 255];
        write_png(&path, ColorType::Rgba, &pixels, 2, 1, None, None);
        assert_eq!(hint_of(&path), AlphaHint::NeedsDecode);
        assert_eq!(
            has_png_transparency_blocking(path.to_str().unwrap()),
            Ok(false)
        );
    }

    #[test]
    fn rgba_with_a_transparent_pixel_reports_transparency() {
        let dir = tmp_dir();
        let path = dir.join("rgba_alpha.png");
        let pixels = [255u8, 0, 0, 255, 0, 255, 0, 0];
        write_png(&path, ColorType::Rgba, &pixels, 2, 1, None, None);
        assert_eq!(
            has_png_transparency_blocking(path.to_str().unwrap()),
            Ok(true)
        );
    }

    /// Colour type 4 was absent from the old match arm, so this reported opaque.
    #[test]
    fn grayscale_alpha_transparency_is_detected() {
        let dir = tmp_dir();
        let path = dir.join("la.png");
        write_png(
            &path,
            ColorType::GrayscaleAlpha,
            &[128, 255, 200, 0],
            2,
            1,
            None,
            None,
        );
        assert_eq!(hint_of(&path), AlphaHint::NeedsDecode);
        assert_eq!(
            has_png_transparency_blocking(path.to_str().unwrap()),
            Ok(true)
        );
    }

    #[test]
    fn grayscale_alpha_fully_opaque_reports_false() {
        let dir = tmp_dir();
        let path = dir.join("la_opaque.png");
        write_png(
            &path,
            ColorType::GrayscaleAlpha,
            &[128, 255, 200, 255],
            2,
            1,
            None,
            None,
        );
        assert_eq!(
            has_png_transparency_blocking(path.to_str().unwrap()),
            Ok(false)
        );
    }

    #[test]
    fn a_non_png_extension_is_ignored() {
        let dir = tmp_dir();
        let path = dir.join("clip.mp4");
        std::fs::write(&path, b"not an image").unwrap();
        assert_eq!(
            has_png_transparency_blocking(path.to_str().unwrap()),
            Ok(false)
        );
    }

    #[test]
    fn an_uppercase_extension_is_still_treated_as_png() {
        let dir = tmp_dir();
        let path = dir.join("SHOUT.PNG");
        let pixels = [255u8, 0, 0, 0];
        write_png(&path, ColorType::Rgba, &pixels, 1, 1, None, None);
        assert_eq!(
            has_png_transparency_blocking(path.to_str().unwrap()),
            Ok(true)
        );
    }

    #[test]
    fn garbage_bytes_do_not_claim_opacity() {
        assert_eq!(
            alpha_hint_from_header(b"nowhere near a png"),
            AlphaHint::NeedsDecode
        );
        assert_eq!(alpha_hint_from_header(&[]), AlphaHint::NeedsDecode);
        assert_eq!(
            alpha_hint_from_header(&PNG_SIGNATURE),
            AlphaHint::NeedsDecode
        );
    }

    #[test]
    fn a_truncated_header_does_not_claim_opacity() {
        let dir = tmp_dir();
        let path = dir.join("cut.png");
        write_png(&path, ColorType::Rgb, &[1, 2, 3], 1, 1, None, None);
        let full = std::fs::read(&path).unwrap();
        let cut = dir.join("cut2.png");
        let mut f = std::fs::File::create(&cut).unwrap();
        f.write_all(&full[..30]).unwrap();
        drop(f);
        assert_eq!(hint_of(&cut), AlphaHint::NeedsDecode);
        // The decode then fails, which surfaces as an error rather than a
        // silent "opaque".
        assert!(has_png_transparency_blocking(cut.to_str().unwrap()).is_err());
    }

    #[test]
    fn a_chunk_length_that_overflows_does_not_claim_opacity() {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&PNG_SIGNATURE);
        bytes.extend_from_slice(&13u32.to_be_bytes());
        bytes.extend_from_slice(b"IHDR");
        bytes.extend_from_slice(&1u32.to_be_bytes()); // width
        bytes.extend_from_slice(&1u32.to_be_bytes()); // height
        bytes.push(8); // bit depth
        bytes.push(2); // colour type: truecolour
        bytes.extend_from_slice(&[0, 0, 0]); // compression, filter, interlace
        bytes.extend_from_slice(&[0, 0, 0, 0]); // CRC
        bytes.extend_from_slice(&u32::MAX.to_be_bytes()); // absurd chunk length
        bytes.extend_from_slice(b"junk");
        assert_eq!(alpha_hint_from_header(&bytes), AlphaHint::NeedsDecode);
    }

    #[tokio::test]
    async fn deleting_an_empty_batch_reports_no_errors() {
        assert!(delete_transparent_pngs_rust(vec![]).await.is_empty());
    }

    #[tokio::test]
    async fn a_missing_file_is_reported_rather_than_swallowed() {
        let errors = delete_transparent_pngs_rust(vec!["definitely/missing.png".into()]).await;
        assert_eq!(errors.len(), 1);
        assert!(
            errors[0].contains("Transparency check failed"),
            "{:?}",
            errors
        );
    }

    #[tokio::test]
    async fn opaque_files_survive_the_sweep() {
        let dir = tmp_dir();
        let path = dir.join("keep.png");
        write_png(&path, ColorType::Rgb, &[1, 2, 3], 1, 1, None, None);
        let errors = delete_transparent_pngs_rust(vec![path.to_str().unwrap().into()]).await;
        assert!(errors.is_empty(), "{:?}", errors);
        assert!(path.exists(), "an opaque png must not be deleted");
    }
}
