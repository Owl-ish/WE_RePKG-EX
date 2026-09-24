use image::{AnimationDecoder, DynamicImage, GenericImageView, ImageDecoder, ImageFormat};
use png::{BitDepth, Decoder};
use std::io::Cursor;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

const MAX_IMAGE_BYTES: u64 = 64 * 1024 * 1024;

/// Reads only the indexed package payload; invalid bounds never become a match.
pub fn segment_matches_file(
    source: &Path,
    offset: u64,
    length: u64,
    counterpart: &Path,
) -> Result<Option<bool>, String> {
    if length == 0 || length > MAX_IMAGE_BYTES {
        return Ok(None);
    }
    let mut package = std::fs::File::open(source).map_err(|error| error.to_string())?;
    let size = package.metadata().map_err(|error| error.to_string())?.len();
    if offset > size || length > size - offset {
        return Ok(None);
    }
    let counterpart_size = std::fs::metadata(counterpart)
        .map_err(|error| error.to_string())?
        .len();
    if counterpart_size == 0 || counterpart_size > MAX_IMAGE_BYTES {
        return Ok(None);
    }
    package
        .seek(SeekFrom::Start(offset))
        .map_err(|error| error.to_string())?;
    let mut first = Vec::with_capacity(length as usize);
    package
        .take(length)
        .read_to_end(&mut first)
        .map_err(|error| error.to_string())?;
    if first.len() as u64 != length {
        return Ok(None);
    }
    let second = std::fs::read(counterpart).map_err(|error| error.to_string())?;
    images_match(&first, &second)
}

fn image_format(bytes: &[u8]) -> Option<ImageFormat> {
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some(ImageFormat::Png)
    } else if bytes.starts_with(b"\xff\xd8\xff") {
        Some(ImageFormat::Jpeg)
    } else if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        Some(ImageFormat::Gif)
    } else {
        None
    }
}

/// Return None when a format detail cannot be compared with the Dart verifier.
pub fn images_match(first: &[u8], second: &[u8]) -> Result<Option<bool>, String> {
    match (image_format(first), image_format(second)) {
        (Some(ImageFormat::Png), Some(ImageFormat::Png)) => pixels_match(first, second),
        (Some(ImageFormat::Jpeg), Some(ImageFormat::Jpeg)) => jpeg_pixels_match(first, second),
        (Some(ImageFormat::Gif), Some(ImageFormat::Gif)) => gif_frames_match(first, second),
        _ => Ok(None),
    }
}

fn jpeg_pixels_match(first: &[u8], second: &[u8]) -> Result<Option<bool>, String> {
    // Colour profiles and EXIF orientation can be interpreted differently by
    // decoders. Let Dart decide those cases instead of risking a false match.
    for bytes in [first, second] {
        if bytes.windows(6).any(|part| part == b"Exif\0\0")
            || bytes.windows(12).any(|part| part == b"ICC_PROFILE\0")
        {
            return Ok(None);
        }
    }
    let decode = |bytes: &[u8]| -> Result<DynamicImage, String> {
        image::load_from_memory_with_format(bytes, ImageFormat::Jpeg)
            .map_err(|error| error.to_string())
    };
    let first_image = decode(first)?;
    let second_image = decode(second)?;
    if first_image.dimensions() != second_image.dimensions() {
        return Ok(Some(false));
    }
    Ok(Some(
        first_image.into_rgba8().into_raw() == second_image.into_rgba8().into_raw(),
    ))
}

fn gif_frames_match(first: &[u8], second: &[u8]) -> Result<Option<bool>, String> {
    let first_decoder = image::codecs::gif::GifDecoder::new(Cursor::new(first))
        .map_err(|error| error.to_string())?;
    let second_decoder = image::codecs::gif::GifDecoder::new(Cursor::new(second))
        .map_err(|error| error.to_string())?;
    if first_decoder.dimensions() != second_decoder.dimensions() {
        return Ok(Some(false));
    }
    let mut first_frames = first_decoder.into_frames();
    let mut second_frames = second_decoder.into_frames();
    let mut frame_count = 0;
    loop {
        match (first_frames.next(), second_frames.next()) {
            (None, None) => return Ok((frame_count > 0).then_some(true)),
            (Some(Ok(a)), Some(Ok(b))) => {
                frame_count += 1;
                if frame_count > 512 {
                    return Ok(None);
                }
                if a.delay() != b.delay() || a.buffer() != b.buffer() {
                    return Ok(Some(false));
                }
            }
            (Some(Err(_)), _) | (_, Some(Err(_))) => return Ok(None),
            _ => return Ok(Some(false)),
        }
    }
}

/// A diagnostic PNG fast path. None leaves unusual encodings to the Dart verifier.
/// These guards are not yet sufficient to authorize deletion from a native result.
pub fn pixels_match(first: &[u8], second: &[u8]) -> Result<Option<bool>, String> {
    let first_header = Decoder::new(Cursor::new(first))
        .read_info()
        .map_err(|error| error.to_string())?;
    let second_header = Decoder::new(Cursor::new(second))
        .read_info()
        .map_err(|error| error.to_string())?;
    let a = first_header.info();
    let b = second_header.info();
    if a.bit_depth != BitDepth::Eight
        || b.bit_depth != BitDepth::Eight
        || a.animation_control.is_some()
        || b.animation_control.is_some()
        || a.source_gamma != b.source_gamma
        || a.source_chromaticities != b.source_chromaticities
        || a.srgb != b.srgb
        || a.icc_profile.as_deref() != b.icc_profile.as_deref()
    {
        return Ok(None);
    }
    let decode = |bytes: &[u8]| -> Result<DynamicImage, String> {
        image::load_from_memory_with_format(bytes, ImageFormat::Png)
            .map_err(|error| error.to_string())
    };
    let first_image = decode(first)?;
    let second_image = decode(second)?;
    if first_image.dimensions() != second_image.dimensions() {
        return Ok(Some(false));
    }
    Ok(Some(
        first_image.into_rgba8().into_raw() == second_image.into_rgba8().into_raw(),
    ))
}
