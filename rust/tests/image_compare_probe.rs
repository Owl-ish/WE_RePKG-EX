use png::{BitDepth, ColorType, Encoder};
#[path = "../src/image_compare.rs"]
mod image_compare;
use image::{codecs::gif::GifEncoder, Delay, Frame, ImageFormat, Rgba, RgbaImage};
use image_compare::pixels_match;
use std::fs;
use std::time::Instant;
use std::time::{SystemTime, UNIX_EPOCH};

fn png_bytes(colour: ColorType, depth: BitDepth, pixels: &[u8], animated: bool) -> Vec<u8> {
    let mut bytes = Vec::new();
    {
        let mut encoder = Encoder::new(&mut bytes, 1, 1);
        encoder.set_color(colour);
        encoder.set_depth(depth);
        if animated {
            encoder.set_animated(1, 0).unwrap();
        }
        let mut writer = encoder.write_header().unwrap();
        writer.write_image_data(pixels).unwrap();
    }
    bytes
}

#[test]
fn opaque_rgb_and_rgba_can_match() {
    let rgb = png_bytes(ColorType::Rgb, BitDepth::Eight, &[20, 40, 60], false);
    let rgba = png_bytes(ColorType::Rgba, BitDepth::Eight, &[20, 40, 60, 255], false);
    assert_eq!(pixels_match(&rgb, &rgba), Ok(Some(true)));
}

#[test]
fn one_changed_channel_does_not_match() {
    let first = png_bytes(ColorType::Rgb, BitDepth::Eight, &[20, 40, 60], false);
    let second = png_bytes(ColorType::Rgb, BitDepth::Eight, &[20, 40, 61], false);
    assert_eq!(pixels_match(&first, &second), Ok(Some(false)));
}

#[test]
fn hidden_rgb_under_zero_alpha_remains_distinct() {
    let first = png_bytes(ColorType::Rgba, BitDepth::Eight, &[20, 40, 60, 0], false);
    let second = png_bytes(ColorType::Rgba, BitDepth::Eight, &[21, 40, 60, 0], false);
    assert_eq!(pixels_match(&first, &second), Ok(Some(false)));
}

#[test]
fn animated_png_needs_the_existing_frame_comparator() {
    let animated = png_bytes(ColorType::Rgb, BitDepth::Eight, &[20, 40, 60], true);
    let still = png_bytes(ColorType::Rgb, BitDepth::Eight, &[20, 40, 60], false);
    assert_eq!(pixels_match(&animated, &still), Ok(None));
}

#[test]
fn sixteen_bit_png_cannot_be_reduced_to_eight_bits() {
    let first = png_bytes(
        ColorType::Grayscale,
        BitDepth::Sixteen,
        &[0x12, 0x34],
        false,
    );
    let second = png_bytes(
        ColorType::Grayscale,
        BitDepth::Sixteen,
        &[0x12, 0x35],
        false,
    );
    assert_eq!(pixels_match(&first, &second), Ok(None));
}

#[test]
fn malformed_png_cannot_match() {
    assert!(pixels_match(b"not a png", b"not a png").is_err());
}

fn jpeg_bytes(rgb: [u8; 3]) -> Vec<u8> {
    let image = image::RgbImage::from_pixel(1, 1, image::Rgb(rgb));
    let mut output = std::io::Cursor::new(Vec::new());
    image.write_to(&mut output, ImageFormat::Jpeg).unwrap();
    output.into_inner()
}

fn gif_bytes(color: [u8; 4], delay_ms: u32, second_frame: bool) -> Vec<u8> {
    let mut output = Vec::new();
    {
        let mut encoder = GifEncoder::new(&mut output);
        let frame = || {
            Frame::from_parts(
                RgbaImage::from_pixel(1, 1, Rgba(color)),
                0,
                0,
                Delay::from_numer_denom_ms(delay_ms, 1),
            )
        };
        encoder.encode_frame(frame()).unwrap();
        if second_frame {
            encoder.encode_frame(frame()).unwrap();
        }
    }
    output
}

#[test]
fn jpeg_pixels_match_and_profile_metadata_defers_to_dart() {
    let first = jpeg_bytes([0, 0, 0]);
    let changed = jpeg_bytes([255, 255, 255]);
    assert_eq!(image_compare::images_match(&first, &first), Ok(Some(true)));
    assert_eq!(
        image_compare::images_match(&first, &changed),
        Ok(Some(false))
    );
    let mut with_exif = first.clone();
    with_exif.extend_from_slice(b"Exif\0\0");
    assert_eq!(image_compare::images_match(&first, &with_exif), Ok(None));
    assert_eq!(
        image_compare::images_match(
            &first,
            &png_bytes(ColorType::Rgb, BitDepth::Eight, &[0, 0, 0], false)
        ),
        Ok(None)
    );
}

#[test]
fn gif_frames_include_pixels_timing_and_count() {
    let first = gif_bytes([255, 0, 0, 255], 100, true);
    let changed_color = gif_bytes([0, 0, 255, 255], 100, true);
    let changed_delay = gif_bytes([255, 0, 0, 255], 200, true);
    let one_frame = gif_bytes([255, 0, 0, 255], 100, false);
    assert_eq!(image_compare::images_match(&first, &first), Ok(Some(true)));
    assert_eq!(
        image_compare::images_match(&first, &changed_color),
        Ok(Some(false))
    );
    assert_eq!(
        image_compare::images_match(&first, &changed_delay),
        Ok(Some(false))
    );
    assert_eq!(
        image_compare::images_match(&first, &one_frame),
        Ok(Some(false))
    );
}

#[test]
fn package_segment_compares_only_bounded_png_bytes() {
    let first = png_bytes(ColorType::Rgb, BitDepth::Eight, &[20, 40, 60], false);
    let changed = png_bytes(ColorType::Rgb, BitDepth::Eight, &[20, 40, 61], false);
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let folder = std::env::temp_dir().join(format!(
        "werepkg-png-segment-{}-{suffix}",
        std::process::id()
    ));
    fs::create_dir(&folder).unwrap();
    let source = folder.join("scene.pkg");
    let counterpart = folder.join("image.png");
    let mut package = b"prefix".to_vec();
    package.extend_from_slice(&first);
    package.extend_from_slice(b"suffix");
    fs::write(&source, package).unwrap();
    fs::write(&counterpart, &first).unwrap();
    assert_eq!(
        image_compare::segment_matches_file(&source, 6, first.len() as u64, &counterpart),
        Ok(Some(true))
    );
    fs::write(&counterpart, changed).unwrap();
    assert_eq!(
        image_compare::segment_matches_file(&source, 6, first.len() as u64, &counterpart),
        Ok(Some(false))
    );
    assert_eq!(
        image_compare::segment_matches_file(&source, u64::MAX, first.len() as u64, &counterpart),
        Ok(None)
    );
    assert_eq!(
        image_compare::segment_matches_file(&source, 6, u64::MAX, &counterpart),
        Ok(None)
    );
    fs::remove_file(source).unwrap();
    fs::remove_file(counterpart).unwrap();
    fs::remove_dir(folder).unwrap();
}

#[test]
fn package_segment_compares_jpeg_and_gif_payloads() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let folder = std::env::temp_dir().join(format!(
        "werepkg-image-segment-{}-{suffix}",
        std::process::id()
    ));
    fs::create_dir(&folder).unwrap();
    let source = folder.join("scene.pkg");
    for (name, original, changed) in [
        (
            "image.jpg",
            jpeg_bytes([0, 0, 0]),
            jpeg_bytes([255, 255, 255]),
        ),
        (
            "image.gif",
            gif_bytes([255, 0, 0, 255], 100, true),
            gif_bytes([0, 0, 255, 255], 100, true),
        ),
    ] {
        let counterpart = folder.join(name);
        let mut package = b"prefix".to_vec();
        package.extend_from_slice(&original);
        fs::write(&source, package).unwrap();
        fs::write(&counterpart, &original).unwrap();
        assert_eq!(
            image_compare::segment_matches_file(&source, 6, original.len() as u64, &counterpart),
            Ok(Some(true))
        );
        fs::write(&counterpart, changed).unwrap();
        assert_eq!(
            image_compare::segment_matches_file(&source, 6, original.len() as u64, &counterpart),
            Ok(Some(false))
        );
        fs::remove_file(counterpart).unwrap();
    }
    fs::remove_file(source).unwrap();
    fs::remove_dir(folder).unwrap();
}

#[test]
#[ignore = "requires a read-only manifest of real image pairs"]
fn probe_real_pairs() {
    let manifest = std::env::var("IMAGE_PROBE_MANIFEST").unwrap();
    for (index, line) in fs::read_to_string(manifest).unwrap().lines().enumerate() {
        let (first, second) = line.split_once('\t').unwrap();
        let timer = Instant::now();
        let first = fs::read(first).unwrap();
        let second = fs::read(second).unwrap();
        let result = image_compare::images_match(&first, &second);
        println!(
            "IMAGE_PAIR {} {:?} {}ms",
            index + 1,
            result,
            timer.elapsed().as_millis()
        );
    }
}
