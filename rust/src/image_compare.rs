use image::{AnimationDecoder, DynamicImage, GenericImageView, ImageDecoder, ImageFormat};
use png::{BitDepth, Decoder};
use std::io::Cursor;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

const MAX_IMAGE_BYTES: u64 = 64 * 1024 * 1024;

/// Streaming exact comparison for package entries; a declined or failed check
/// leaves Dart's cancellable comparer responsible for the verdict.
pub fn exact_segment_matches_file(
    source: &Path,
    offset: u64,
    length: u64,
    counterpart: &Path,
) -> Result<Option<bool>, String> {
    if length > MAX_IMAGE_BYTES {
        return Ok(None);
    }
    let mut first = std::fs::File::open(source).map_err(|error| error.to_string())?;
    let source_size = first.metadata().map_err(|error| error.to_string())?.len();
    if offset > source_size || length > source_size - offset {
        return Ok(None);
    }
    let mut second = std::fs::File::open(counterpart).map_err(|error| error.to_string())?;
    if second.metadata().map_err(|error| error.to_string())?.len() != length {
        return Ok(Some(false));
    }
    first
        .seek(SeekFrom::Start(offset))
        .map_err(|error| error.to_string())?;
    let mut left = [0_u8; 64 * 1024];
    let mut right = [0_u8; 64 * 1024];
    let mut remaining = length;
    while remaining > 0 {
        let count = remaining.min(left.len() as u64) as usize;
        first
            .read_exact(&mut left[..count])
            .map_err(|error| error.to_string())?;
        second
            .read_exact(&mut right[..count])
            .map_err(|error| error.to_string())?;
        if left[..count] != right[..count] {
            return Ok(Some(false));
        }
        remaining -= count as u64;
    }
    Ok(Some(true))
}

pub struct RawTextureSpec {
    pub offset: u64,
    pub length: u64,
    pub decoded_length: u64,
    pub format: u32,
    pub texture_width: u32,
    pub texture_height: u32,
    pub image_width: u32,
    pub image_height: u32,
    pub compressed: bool,
}

/// Compares only the primary image, including its cropped dimensions. A
/// declined layout keeps Dart responsible for the existing verdict.
pub fn raw_texture_matches_png(
    source: &Path,
    spec: &RawTextureSpec,
    generated: &Path,
) -> Result<Option<bool>, String> {
    if spec.length == 0
        || spec.length > MAX_IMAGE_BYTES
        || spec.decoded_length == 0
        || spec.decoded_length > MAX_IMAGE_BYTES
        || spec.image_width == 0
        || spec.image_height == 0
        || spec.image_width > spec.texture_width
        || spec.image_height > spec.texture_height
    {
        return Ok(None);
    }
    let block_bytes = match spec.format {
        4 | 6 => 16_u64,
        7 => 8,
        0 | 8 | 9 => 0,
        _ => return Ok(None),
    };
    let expected = if block_bytes == 0 {
        let channels = match spec.format {
            0 => 4_u64,
            8 => 2,
            _ => 1,
        };
        u64::from(spec.texture_width)
            .checked_mul(u64::from(spec.texture_height))
            .and_then(|value| value.checked_mul(channels))
    } else {
        u64::from(spec.texture_width.div_ceil(4))
            .checked_mul(u64::from(spec.texture_height.div_ceil(4)))
            .and_then(|value| value.checked_mul(block_bytes))
    };
    if expected != Some(spec.decoded_length)
        || (!spec.compressed && spec.length != spec.decoded_length)
        || u64::from(spec.texture_width)
            .checked_mul(u64::from(spec.texture_height))
            .and_then(|value| value.checked_mul(4))
            .is_none_or(|value| value > MAX_IMAGE_BYTES)
    {
        return Ok(None);
    }
    let mut input = std::fs::File::open(source).map_err(|error| error.to_string())?;
    let size = input.metadata().map_err(|error| error.to_string())?.len();
    if spec.offset > size || spec.length > size - spec.offset {
        return Ok(None);
    }
    input
        .seek(SeekFrom::Start(spec.offset))
        .map_err(|error| error.to_string())?;
    let mut payload = Vec::with_capacity(spec.length as usize);
    input
        .take(spec.length)
        .read_to_end(&mut payload)
        .map_err(|error| error.to_string())?;
    if payload.len() as u64 != spec.length {
        return Ok(None);
    }
    let pixels = if spec.compressed {
        match decode_lz4_block(&payload, spec.decoded_length as usize) {
            Some(value) => value,
            None => return Ok(None),
        }
    } else {
        payload
    };
    let png = std::fs::read(generated).map_err(|error| error.to_string())?;
    if png.len() as u64 > MAX_IMAGE_BYTES || !png.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Ok(None);
    }
    let header = Decoder::new(Cursor::new(&png))
        .read_info()
        .map_err(|error| error.to_string())?;
    let info = header.info();
    if info.width != spec.image_width
        || info.height != spec.image_height
        || info.bit_depth != BitDepth::Eight
        || info.animation_control.is_some()
        || info.source_gamma.is_some()
        || info.source_chromaticities.is_some()
        || info.srgb.is_some()
        || info.icc_profile.is_some()
    {
        return Ok(None);
    }
    let decoded = image::load_from_memory_with_format(&png, ImageFormat::Png)
        .map_err(|error| error.to_string())?;
    if decoded.dimensions() != (spec.image_width, spec.image_height) {
        return Ok(None);
    }
    let rgba = decoded.into_rgba8().into_raw();
    if block_bytes != 0 {
        return Ok(Some(dxt_matches_rgba(&pixels, spec, &rgba)));
    }
    let channels = match spec.format {
        0 => 4_usize,
        8 => 2,
        _ => 1,
    };
    for y in 0..spec.image_height as usize {
        for x in 0..spec.image_width as usize {
            let source = (y * spec.texture_width as usize + x) * channels;
            let target = (y * spec.image_width as usize + x) * 4;
            let red = match spec.format {
                8 => pixels[source + 1],
                _ => pixels[source],
            };
            let expected = if spec.format == 0 {
                [
                    pixels[source],
                    pixels[source + 1],
                    pixels[source + 2],
                    pixels[source + 3],
                ]
            } else {
                [
                    red,
                    red,
                    red,
                    if spec.format == 8 {
                        pixels[source]
                    } else {
                        255
                    },
                ]
            };
            if rgba[target..target + 4] != expected {
                return Ok(Some(false));
            }
        }
    }
    Ok(Some(true))
}

fn decode_lz4_block(source: &[u8], output_length: usize) -> Option<Vec<u8>> {
    let mut output = Vec::with_capacity(output_length);
    let mut at = 0;
    while at < source.len() {
        let token = source[at];
        at += 1;
        let mut literals = usize::from(token >> 4);
        if literals == 15 {
            loop {
                let extra = *source.get(at)?;
                at += 1;
                literals = literals.checked_add(usize::from(extra))?;
                if extra != 255 {
                    break;
                }
            }
        }
        let end = at.checked_add(literals)?;
        if end > source.len() || output.len().checked_add(literals)? > output_length {
            return None;
        }
        output.extend_from_slice(&source[at..end]);
        at = end;
        if at == source.len() {
            break;
        }
        let distance = usize::from(*source.get(at)?) | (usize::from(*source.get(at + 1)?) << 8);
        at += 2;
        if distance == 0 || distance > output.len() {
            return None;
        }
        let mut count = usize::from(token & 15) + 4;
        if token & 15 == 15 {
            loop {
                let extra = *source.get(at)?;
                at += 1;
                count = count.checked_add(usize::from(extra))?;
                if extra != 255 {
                    break;
                }
            }
        }
        if output.len().checked_add(count)? > output_length {
            return None;
        }
        for _ in 0..count {
            let value = output[output.len() - distance];
            output.push(value);
        }
    }
    (output.len() == output_length).then_some(output)
}

fn dxt_matches_rgba(blocks: &[u8], spec: &RawTextureSpec, rgba: &[u8]) -> bool {
    let block_bytes = if spec.format == 7 { 8 } else { 16 };
    let mut block = 0;
    for by in (0..spec.texture_height).step_by(4) {
        for bx in (0..spec.texture_width).step_by(4) {
            let color_at = block + if spec.format == 7 { 0 } else { 8 };
            let endpoint0 = u16::from_le_bytes([blocks[color_at], blocks[color_at + 1]]);
            let endpoint1 = u16::from_le_bytes([blocks[color_at + 2], blocks[color_at + 3]]);
            let mut colors = [[0_u8; 4]; 4];
            for (index, endpoint) in [endpoint0, endpoint1].into_iter().enumerate() {
                colors[index] = [
                    ((endpoint >> 11) as u8 & 31) * 8 | ((endpoint >> 11) as u8 & 31) >> 2,
                    ((endpoint >> 5) as u8 & 63) * 4 | ((endpoint >> 5) as u8 & 63) >> 4,
                    (endpoint as u8 & 31) * 8 | (endpoint as u8 & 31) >> 2,
                    255,
                ];
            }
            let transparent = spec.format == 7 && endpoint0 <= endpoint1;
            for channel in 0..3 {
                let first = u16::from(colors[0][channel]);
                let second = u16::from(colors[1][channel]);
                colors[2][channel] = if transparent {
                    ((first + second) / 2) as u8
                } else {
                    ((2 * first + second) / 3) as u8
                };
                colors[3][channel] = if transparent {
                    0
                } else {
                    ((first + 2 * second) / 3) as u8
                };
            }
            colors[2][3] = 255;
            colors[3][3] = if transparent { 0 } else { 255 };
            let mut alphas = [0_u8; 8];
            let mut alpha_indices = 0_u64;
            if spec.format == 4 {
                alphas[0] = blocks[block];
                alphas[1] = blocks[block + 1];
                if alphas[0] > alphas[1] {
                    for index in 1..=6 {
                        let position = index as u16;
                        alphas[index + 1] = (((7 - position) * u16::from(alphas[0])
                            + position * u16::from(alphas[1]))
                            / 7) as u8;
                    }
                } else {
                    for index in 1..=4 {
                        let position = index as u16;
                        alphas[index + 1] = (((5 - position) * u16::from(alphas[0])
                            + position * u16::from(alphas[1]))
                            / 5) as u8;
                    }
                    alphas[6] = 0;
                    alphas[7] = 255;
                }
                for index in 0..6 {
                    alpha_indices |= u64::from(blocks[block + 2 + index]) << (index * 8);
                }
            }
            for py in 0..4 {
                for px in 0..4 {
                    let x = bx + px;
                    let y = by + py;
                    if x >= spec.image_width || y >= spec.image_height {
                        continue;
                    }
                    let pixel = (py * 4 + px) as usize;
                    let color_index = (blocks[color_at + 4 + py as usize] >> (px * 2)) & 3;
                    let color = colors[color_index as usize];
                    let alpha = match spec.format {
                        4 => alphas[((alpha_indices >> (pixel * 3)) & 7) as usize],
                        6 => ((blocks[block + pixel / 2] >> ((pixel & 1) * 4)) & 15) * 17,
                        _ => color[3],
                    };
                    let target = (y as usize * spec.image_width as usize + x as usize) * 4;
                    if rgba[target..target + 4] != [color[0], color[1], color[2], alpha] {
                        return false;
                    }
                }
            }
            block += block_bytes;
        }
    }
    block == blocks.len()
}

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
