use std::collections::HashMap;
use std::io::Read;
use std::path::{Path, PathBuf};
#[cfg(windows)]
use std::os::windows::fs::MetadataExt;
#[cfg(not(windows))]
use std::time::UNIX_EPOCH;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc, Mutex,
};

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

/// True when every alpha is zero, and there is at least one pixel to say so.
fn all_invisible(alphas: impl Iterator<Item = u32>) -> bool {
    let mut alphas = alphas.peekable();
    alphas.peek().is_some() && alphas.all(|alpha| alpha == 0)
}

/// Blocking check: header fast path first, full decode only when the header
/// cannot settle it.
fn is_png_fully_transparent_blocking(file_path: &str) -> Result<bool, String> {
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
    // Wholly invisible, not merely carrying an alpha channel. Deleting anything
    // with one soft pixel took the artwork with the masks. LumaA (colour type 4)
    // is listed because a grayscale mask used to read as opaque and survive.
    Ok(match img {
        image::DynamicImage::ImageRgba8(img) => all_invisible(img.pixels().map(|p| p.0[3] as u32)),
        image::DynamicImage::ImageRgba16(img) => all_invisible(img.pixels().map(|p| p.0[3] as u32)),
        image::DynamicImage::ImageLumaA8(img) => all_invisible(img.pixels().map(|p| p.0[1] as u32)),
        image::DynamicImage::ImageLumaA16(img) => {
            all_invisible(img.pixels().map(|p| p.0[1] as u32))
        }
        _ => false, // 非RGBA格式没有透明度通道
    })
}

#[flutter_rust_bridge::frb]
pub async fn is_png_fully_transparent_rust(file_path: String) -> Result<bool, String> {
    // Decoding is blocking CPU work. Running it directly on an async worker
    // starved the runtime once a batch was in flight.
    tokio::task::spawn_blocking(move || is_png_fully_transparent_blocking(&file_path))
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
            match is_png_fully_transparent_rust(file_path.clone()).await {
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

const REBUILT_SHADER_DIR: &str = r"shaders\blobssm40\";

fn normalise_relative(path: &Path) -> String {
    // Match Dart's per-character lowercase mapping, without contextual expansions.
    path.to_string_lossy()
        .replace('/', "\\")
        .chars()
        .flat_map(|character| character.to_lowercase().take(1))
        .collect()
}

fn is_rebuilt_shader_path_rust(relative: &Path) -> bool {
    normalise_relative(relative).starts_with(REBUILT_SHADER_DIR)
}

/// Walks one wallpaper tree without following links.
///
/// DirectoryEntry metadata gives the file size while Windows is already
/// enumerating the tree, avoiding the extra Dart stat call for every file.
fn walk_wallpaper_files<F>(root: &Path, mut visit: F) -> std::io::Result<bool>
where
    F: FnMut(&Path, u64) -> bool,
{
    let mut pending = vec![root.to_path_buf()];

    while let Some(folder) = pending.pop() {
        for entry in std::fs::read_dir(folder)? {
            let entry = entry?;
            let kind = entry.file_type()?;
            let file_path = entry.path();

            if kind.is_dir() {
                pending.push(file_path);
            } else if kind.is_file() {
                let relative = file_path
                    .strip_prefix(root)
                    .map_err(std::io::Error::other)?;
                if is_rebuilt_shader_path_rust(relative) {
                    continue;
                }
                if !visit(relative, entry.metadata()?.len()) {
                    return Ok(false);
                }
            }
        }
    }

    Ok(true)
}

/// True when live and backup contain the same meaningful paths and sizes.
fn backup_matches_live(live: &Path, backup: &Path) -> std::io::Result<bool> {
    if !live.is_dir() || !backup.is_dir() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "wallpaper folder is missing",
        ));
    }

    let mut live_files = HashMap::<String, u64>::new();
    walk_wallpaper_files(live, |relative, size| {
        live_files.insert(normalise_relative(relative), size);
        true
    })?;

    let mut backup_files = HashMap::<String, u64>::new();
    walk_wallpaper_files(backup, |relative, size| {
        backup_files.insert(normalise_relative(relative), size);
        true
    })?;
    Ok(live_files == backup_files)
}

fn compare_backup_folders_blocking(
    live_root: String,
    backup_root: String,
    folder_names: Vec<String>,
    workers: u32,
) -> HashMap<String, bool> {
    if folder_names.is_empty() {
        return HashMap::new();
    }

    let names = Arc::new(folder_names);
    let next = Arc::new(AtomicUsize::new(0));
    let results = Arc::new(Mutex::new(HashMap::<String, bool>::new()));
    let worker_count = (workers as usize).clamp(1, 64).min(names.len());
    let mut handles = Vec::with_capacity(worker_count);

    for _ in 0..worker_count {
        let names = Arc::clone(&names);
        let next = Arc::clone(&next);
        let results = Arc::clone(&results);
        let live_root = PathBuf::from(&live_root);
        let backup_root = PathBuf::from(&backup_root);

        handles.push(std::thread::spawn(move || loop {
            let index = next.fetch_add(1, Ordering::Relaxed);
            if index >= names.len() {
                break;
            }

            let name = &names[index];
            let standing = backup_matches_live(&live_root.join(name), &backup_root.join(name));
            if let Ok(covers) = standing {
                results.lock().unwrap().insert(name.clone(), covers);
            }
        }));
    }

    for handle in handles {
        let _ = handle.join();
    }

    let snapshot = results.lock().unwrap().clone();
    snapshot
}

/// Compares the named recursive wallpaper folders in parallel.
///
/// The map contains only readable pairs: true means the meaningful trees match;
/// false means a file is missing, extra, or has a different size.
/// Unreadable pairs are omitted so Dart keeps the same no-verdict behaviour.
#[flutter_rust_bridge::frb]
pub async fn compare_backup_folders_rust(
    live_root: String,
    backup_root: String,
    folder_names: Vec<String>,
    workers: u32,
) -> Result<HashMap<String, bool>, String> {
    tokio::task::spawn_blocking(move || {
        compare_backup_folders_blocking(live_root, backup_root, folder_names, workers)
    })
    .await
    .map_err(|e| format!("Task execution error: {}", e))
}



/// True when a wallpaper folder is empty or contains only disposable files.
///
/// Live folders allow only .dxs shader-cache files. Backup folders additionally
/// allow the rebuilt shaders/blobsSM40 tree. Links reject the folder so native
/// scanning preserves Dart's followLinks: false maintenance semantics.
fn wallpaper_folder_is_junk(folder: &Path, backup: bool) -> std::io::Result<bool> {
    if !folder.is_dir() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "wallpaper folder is missing",
        ));
    }

    let mut pending = std::collections::VecDeque::from([folder.to_path_buf()]);
    while let Some(current) = pending.pop_front() {
        for entry in std::fs::read_dir(current)? {
            let entry = entry?;
            let kind = entry.file_type()?;
            let entry_path = entry.path();

            if kind.is_symlink() {
                return Ok(false);
            }
            if kind.is_dir() {
                pending.push_back(entry_path);
                continue;
            }
            if !kind.is_file() {
                continue;
            }

            let relative = entry_path
                .strip_prefix(folder)
                .map_err(std::io::Error::other)?;
            let is_dxs = relative
                .extension()
                .and_then(|extension| extension.to_str())
                .is_some_and(|extension| extension.eq_ignore_ascii_case("dxs"));
            if !is_dxs && !(backup && is_rebuilt_shader_path_rust(relative)) {
                return Ok(false);
            }
        }
    }

    Ok(true)
}

fn find_junk_folders_blocking(
    root: String,
    folder_names: Vec<String>,
    backup: bool,
    workers: u32,
) -> Vec<String> {
    if folder_names.is_empty() {
        return Vec::new();
    }

    let names = Arc::new(folder_names);
    let next = Arc::new(AtomicUsize::new(0));
    let results = Arc::new(Mutex::new(Vec::<String>::new()));
    let worker_count = (workers as usize).clamp(1, 64).min(names.len());
    let mut handles = Vec::with_capacity(worker_count);

    for _ in 0..worker_count {
        let names = Arc::clone(&names);
        let next = Arc::clone(&next);
        let results = Arc::clone(&results);
        let root = PathBuf::from(&root);

        handles.push(std::thread::spawn(move || loop {
            let index = next.fetch_add(1, Ordering::Relaxed);
            if index >= names.len() {
                break;
            }

            let name = &names[index];
            if matches!(wallpaper_folder_is_junk(&root.join(name), backup), Ok(true)) {
                results.lock().unwrap().push(name.clone());
            }
        }));
    }

    for handle in handles {
        let _ = handle.join();
    }

    let snapshot = results.lock().unwrap().clone();
    snapshot
}

/// Finds empty/cache-only wallpaper folders in parallel.
///
/// Missing or unreadable folders are omitted, matching the Dart maintenance
/// pass where those cases are simply not classified as junk.
#[flutter_rust_bridge::frb]
pub async fn find_junk_folders_rust(
    root: String,
    folder_names: Vec<String>,
    backup: bool,
    workers: u32,
) -> Result<Vec<String>, String> {
    tokio::task::spawn_blocking(move || {
        find_junk_folders_blocking(root, folder_names, backup, workers)
    })
    .await
    .map_err(|e| format!("Task execution error: {}", e))
}

#[derive(Clone, Debug)]
pub struct IntegrityFolderEntryRead {
    pub name: String,
    pub is_directory: bool,
}

#[derive(Clone, Debug)]
pub struct IntegrityFolderRead {
    pub entries: Vec<IntegrityFolderEntryRead>,
    pub project_present: bool,
    pub project_json: Option<String>,
}

fn read_integrity_folders_blocking(
    root: String,
    folder_names: Vec<String>,
    workers: u32,
) -> HashMap<String, IntegrityFolderRead> {
    if folder_names.is_empty() {
        return HashMap::new();
    }

    let root = PathBuf::from(root);
    let names = Arc::new(folder_names);
    let next = Arc::new(AtomicUsize::new(0));
    let results = Arc::new(Mutex::new(HashMap::<String, IntegrityFolderRead>::new()));
    let worker_count = (workers as usize).clamp(1, 64).min(names.len());
    let mut handles = Vec::with_capacity(worker_count);

    for _ in 0..worker_count {
        let root = root.clone();
        let names = Arc::clone(&names);
        let next = Arc::clone(&next);
        let results = Arc::clone(&results);

        handles.push(std::thread::spawn(move || loop {
            let index = next.fetch_add(1, Ordering::Relaxed);
            if index >= names.len() {
                break;
            }

            let name = &names[index];
            let folder = root.join(name);
            let Ok(read_dir) = std::fs::read_dir(&folder) else {
                continue;
            };
            let mut entries = Vec::<IntegrityFolderEntryRead>::new();
            let mut readable = true;
            let mut project_present = false;

            for entry in read_dir {
                let Ok(entry) = entry else {
                    readable = false;
                    break;
                };
                let Ok(kind) = entry.file_type() else {
                    readable = false;
                    break;
                };
                let entry_name = entry.file_name().to_string_lossy().into_owned();
                let is_directory = if kind.is_symlink() {
                    entry.path().is_dir()
                } else {
                    kind.is_dir()
                };
                if !is_directory && entry_name.eq_ignore_ascii_case("project.json") {
                    project_present = true;
                }
                entries.push(IntegrityFolderEntryRead {
                    name: entry_name,
                    is_directory,
                });
            }

            if !readable {
                continue;
            }
            let project_json = if project_present {
                std::fs::read_to_string(folder.join("project.json")).ok()
            } else {
                None
            };
            results.lock().unwrap().insert(
                name.clone(),
                IntegrityFolderRead {
                    entries,
                    project_present,
                    project_json,
                },
            );
        }));
    }

    for handle in handles {
        let _ = handle.join();
    }

    let snapshot = results.lock().unwrap().clone();
    snapshot
}

/// Reads each wallpaper folder's top-level entries and project.json in one
/// native batch. Unreadable or vanished folders are omitted so Dart keeps the
/// integrity scan's existing skip behavior.
#[flutter_rust_bridge::frb]
pub async fn read_integrity_folders_rust(
    root: String,
    folder_names: Vec<String>,
    workers: u32,
) -> Result<HashMap<String, IntegrityFolderRead>, String> {
    tokio::task::spawn_blocking(move || {
        read_integrity_folders_blocking(root, folder_names, workers)
    })
    .await
    .map_err(|e| format!("Task execution error: {}", e))
}

#[derive(Clone, Debug)]
pub struct WallpaperProjectRead {
    pub json: String,
    /// Matches Dart FileStat.changed on Windows: project.json creation time.
    pub changed_micros: f64,
}

#[cfg(windows)]
fn file_changed_micros(metadata: &std::fs::Metadata) -> f64 {
    // Dart FileStat.changed uses Windows creation time at whole-second precision.
    const WINDOWS_TO_UNIX_EPOCH_100NS: i128 = 116_444_736_000_000_000;
    (metadata.creation_time() as i128 - WINDOWS_TO_UNIX_EPOCH_100NS)
        .div_euclid(10_000_000) as f64 * 1_000_000.0
}

#[cfg(not(windows))]
fn file_changed_micros(metadata: &std::fs::Metadata) -> f64 {
    let time = metadata.created().or_else(|_| metadata.modified()).unwrap_or(UNIX_EPOCH);
    match time.duration_since(UNIX_EPOCH) {
        Ok(value) => value.as_micros() as f64,
        Err(value) => -(value.duration().as_micros() as f64),
    }
}

fn read_wallpaper_projects_blocking(
    root: String,
    folder_names: Vec<String>,
    workers: u32,
) -> HashMap<String, WallpaperProjectRead> {
    if folder_names.is_empty() {
        return HashMap::new();
    }

    let names = Arc::new(folder_names);
    let next = Arc::new(AtomicUsize::new(0));
    let results = Arc::new(Mutex::new(HashMap::<String, WallpaperProjectRead>::new()));
    let worker_count = (workers as usize).clamp(1, 64).min(names.len());
    let mut handles = Vec::with_capacity(worker_count);

    for _ in 0..worker_count {
        let names = Arc::clone(&names);
        let next = Arc::clone(&next);
        let results = Arc::clone(&results);
        let root = PathBuf::from(&root);

        handles.push(std::thread::spawn(move || loop {
            let index = next.fetch_add(1, Ordering::Relaxed);
            if index >= names.len() {
                break;
            }

            let name = &names[index];
            let project = root.join(name).join("project.json");
            let Ok(mut file) = std::fs::File::open(&project) else {
                continue;
            };
            let Ok(metadata) = file.metadata() else {
                continue;
            };
            let mut json = String::new();
            if file.read_to_string(&mut json).is_err() {
                continue;
            }
            results.lock().unwrap().insert(
                name.clone(),
                WallpaperProjectRead {
                    json,
                    changed_micros: file_changed_micros(&metadata),
                },
            );
        }));
    }

    for handle in handles {
        let _ = handle.join();
    }

    let snapshot = results.lock().unwrap().clone();
    snapshot
}

/// Reads project.json plus the timestamp the Dart grids already use, in one
/// native batch. Missing or unreadable files are omitted. JSON stays raw so
/// Dart keeps the app's existing field coercion and parse-error behavior.
#[flutter_rust_bridge::frb]
pub async fn read_wallpaper_projects_rust(
    root: String,
    folder_names: Vec<String>,
    workers: u32,
) -> Result<HashMap<String, WallpaperProjectRead>, String> {
    tokio::task::spawn_blocking(move || {
        read_wallpaper_projects_blocking(root, folder_names, workers)
    })
    .await
    .map_err(|e| format!("Task execution error: {}", e))
}


fn folder_version_token(folder: &Path) -> std::io::Result<Option<String>> {
    let mut stamps = Vec::<(String, u64, i128)>::new();
    for entry in std::fs::read_dir(folder)? {
        let entry = entry?;
        // Follow readable links; Dart leaves dangling links out of file tokens.
        let kind = entry.file_type()?;
        if !kind.is_file() && !kind.is_symlink() {
            continue;
        }
        let metadata = if kind.is_symlink() {
            match std::fs::metadata(entry.path()) {
                Ok(metadata) => metadata,
                Err(_) => continue,
            }
        } else {
            entry.metadata()?
        };
        if !metadata.is_file() {
            continue;
        }
        let modified = metadata.modified()?;
        let millis = match modified.duration_since(std::time::UNIX_EPOCH) {
            Ok(duration) => duration.as_millis() as i128,
            Err(error) => -(error.duration().as_millis() as i128),
        };
        // Dart FileStat on Windows exposes whole seconds. Keep saved tokens compatible.
        #[cfg(windows)]
        let millis = millis.div_euclid(1000) * 1000;
        stamps.push((
            entry.file_name().to_string_lossy().into_owned(),
            metadata.len(),
            millis,
        ));
    }
    if stamps.is_empty() {
        return Ok(None);
    }
    stamps.sort_by(|a, b| a.0.encode_utf16().cmp(b.0.encode_utf16()));
    Ok(Some(
        stamps
            .into_iter()
            .map(|(name, size, modified)| format!("{}|{}|{}", name, size, modified))
            .collect::<Vec<_>>()
            .join(";"),
    ))
}

fn my_projects_inventory_blocking(
    root: String,
    ignored_prefixes: Vec<String>,
    workers: u32,
) -> Result<HashMap<String, Option<String>>, String> {
    let root = PathBuf::from(root);
    if !root.is_dir() {
        return Ok(HashMap::new());
    }

    let mut names = Vec::<String>::new();
    let entries = std::fs::read_dir(&root).map_err(|e| e.to_string())?;
    for entry in entries {
        let entry = entry.map_err(|e| e.to_string())?;
        let kind = entry.file_type().map_err(|e| e.to_string())?;
        if !kind.is_dir() && !(kind.is_symlink() && entry.path().is_dir()) {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        if ignored_prefixes.iter().any(|prefix| name.starts_with(prefix)) {
            continue;
        }
        names.push(name);
    }

    if names.is_empty() {
        return Ok(HashMap::new());
    }

    let names = Arc::new(names);
    let next = Arc::new(AtomicUsize::new(0));
    let results = Arc::new(Mutex::new(HashMap::<String, Option<String>>::new()));
    let worker_count = (workers as usize).clamp(1, 64).min(names.len());
    let mut handles = Vec::with_capacity(worker_count);

    for _ in 0..worker_count {
        let names = Arc::clone(&names);
        let next = Arc::clone(&next);
        let results = Arc::clone(&results);
        let root = root.clone();

        handles.push(std::thread::spawn(move || loop {
            let index = next.fetch_add(1, Ordering::Relaxed);
            if index >= names.len() {
                break;
            }

            let name = &names[index];
            let version = folder_version_token(&root.join(name)).ok().flatten();
            results.lock().unwrap().insert(name.clone(), version);
        }));
    }

    for handle in handles {
        let _ = handle.join();
    }

    let snapshot = results.lock().unwrap().clone();
    Ok(snapshot)
}

/// Lists MyProjects folders and computes their top-level-file version tokens in
/// one native pass. Every visible folder is returned; a null value means the
/// folder had no top-level files or became unreadable after enumeration.
#[flutter_rust_bridge::frb]
pub async fn my_projects_inventory_rust(
    root: String,
    ignored_prefixes: Vec<String>,
    workers: u32,
) -> Result<HashMap<String, Option<String>>, String> {
    tokio::task::spawn_blocking(move || {
        my_projects_inventory_blocking(root, ignored_prefixes, workers)
    })
    .await
    .map_err(|e| format!("Task execution error: {}", e))?
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
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
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
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
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
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
            Ok(false)
        );
    }

    /// palette alpha lives in tRNS, not the colour type byte.
    /// Answering from the colour type alone would call this opaque and never
    /// look at the pixels.
    #[test]
    fn indexed_with_trns_falls_through_to_the_decode() {
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
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
            Ok(false),
            "half the pixels are visible"
        );
    }

    #[test]
    fn an_indexed_image_drawn_only_in_the_clear_entry_is_reported() {
        let dir = tmp_dir();
        let path = dir.join("pal_trns_blank.png");
        write_png(
            &path,
            ColorType::Indexed,
            &[0, 0, 0, 0],
            2,
            2,
            Some(vec![255, 0, 0, 0, 255, 0]),
            Some(vec![0, 255]),
        );
        assert_eq!(
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
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
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
            Ok(false)
        );
    }

    /// No alpha channel at all, so the verdict rests entirely on tRNS naming the
    /// one colour the image is drawn in.
    #[test]
    fn a_truecolour_image_drawn_only_in_the_clear_colour_is_reported() {
        let dir = tmp_dir();
        let path = dir.join("rgb_trns_blank.png");
        let pixels = [255u8, 0, 0, 255, 0, 0];
        write_png(
            &path,
            ColorType::Rgb,
            &pixels,
            2,
            1,
            None,
            Some(vec![0, 255, 0, 0, 0, 0]), // pure red reads as transparent
        );
        assert_eq!(
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
            Ok(true)
        );
    }

    #[test]
    fn a_fully_opaque_rgba_image_is_kept() {
        let dir = tmp_dir();
        let path = dir.join("rgba_opaque.png");
        let pixels = [255u8, 0, 0, 255, 0, 255, 0, 255];
        write_png(&path, ColorType::Rgba, &pixels, 2, 1, None, None);
        assert_eq!(hint_of(&path), AlphaHint::NeedsDecode);
        assert_eq!(
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
            Ok(false)
        );
    }

    /// The setting used to mean "carries any transparency", so a photograph with
    /// one soft pixel went to the recycle bin and the export came out empty.
    #[test]
    fn rgba_with_one_transparent_pixel_is_kept() {
        let dir = tmp_dir();
        let path = dir.join("rgba_alpha.png");
        let pixels = [255u8, 0, 0, 255, 0, 255, 0, 0];
        write_png(&path, ColorType::Rgba, &pixels, 2, 1, None, None);
        assert_eq!(
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
            Ok(false)
        );
    }

    #[test]
    fn rgba_with_every_pixel_invisible_is_reported() {
        let dir = tmp_dir();
        let path = dir.join("rgba_blank.png");
        let pixels = [255u8, 0, 0, 0, 0, 255, 0, 0];
        write_png(&path, ColorType::Rgba, &pixels, 2, 1, None, None);
        assert_eq!(
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
            Ok(true)
        );
    }

    /// Colour type 4 was absent from the match arm once, so grayscale never
    /// reached the pixels at all.
    #[test]
    fn a_grayscale_alpha_image_with_every_pixel_invisible_is_reported() {
        let dir = tmp_dir();
        let path = dir.join("la.png");
        write_png(
            &path,
            ColorType::GrayscaleAlpha,
            &[128, 0, 200, 0],
            2,
            1,
            None,
            None,
        );
        assert_eq!(hint_of(&path), AlphaHint::NeedsDecode);
        assert_eq!(
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
            Ok(true)
        );
    }

    #[test]
    fn a_fully_opaque_grayscale_alpha_image_is_kept() {
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
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
            Ok(false)
        );
    }

    #[test]
    fn a_non_png_extension_is_ignored() {
        let dir = tmp_dir();
        let path = dir.join("clip.mp4");
        std::fs::write(&path, b"not an image").unwrap();
        assert_eq!(
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
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
            is_png_fully_transparent_blocking(path.to_str().unwrap()),
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
        assert!(is_png_fully_transparent_blocking(cut.to_str().unwrap()).is_err());
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
    async fn artwork_survives_the_sweep() {
        let dir = tmp_dir();
        let opaque = dir.join("keep.png");
        write_png(&opaque, ColorType::Rgb, &[1, 2, 3], 1, 1, None, None);
        let soft_edge = dir.join("photo.png");
        write_png(
            &soft_edge,
            ColorType::Rgba,
            &[255, 0, 0, 255, 0, 255, 0, 0],
            2,
            1,
            None,
            None,
        );

        let errors = delete_transparent_pngs_rust(vec![
            opaque.to_str().unwrap().into(),
            soft_edge.to_str().unwrap().into(),
        ])
        .await;

        assert!(errors.is_empty(), "{:?}", errors);
        assert!(opaque.exists(), "an opaque png must not be deleted");
        assert!(soft_edge.exists(), "one soft pixel is not a mask");
    }

    fn write_backup_fixture(root: &Path, relative: &str, bytes: &[u8]) {
        let file = root.join(relative);
        std::fs::create_dir_all(file.parent().unwrap()).unwrap();
        std::fs::write(file, bytes).unwrap();
    }

    #[test]
    fn filename_keys_preserve_unicode_and_use_simple_lowercase() {
        assert_eq!(
            normalise_relative(Path::new("中文/日本語/한국어🌸/Ä.PNG")),
            "中文\\日本語\\한국어🌸\\ä.png"
        );
        assert_eq!(normalise_relative(Path::new("ΟΣ")), "οσ");
        assert_eq!(normalise_relative(Path::new("İ")), "i");
        assert_eq!(normalise_relative(Path::new("\u{10400}")), "\u{10428}");
        assert_ne!(
            normalise_relative(Path::new("é")),
            normalise_relative(Path::new("e\u{301}"))
        );
    }

    #[test]
    fn version_token_orders_supplementary_names_as_utf16() {
        let root = tmp_dir();
        write_backup_fixture(&root, "\u{10000}.txt", b"a");
        write_backup_fixture(&root, "\u{e000}.txt", b"b");
        let token = folder_version_token(&root).unwrap().unwrap();
        assert!(token.starts_with("\u{10000}.txt|1|"));
        #[cfg(windows)]
        for entry in token.split(';') {
            let millis: i128 = entry.rsplit('|').next().unwrap().parse().unwrap();
            assert_eq!(millis % 1000, 0);
        }
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn recursive_backup_comparison_reports_backup_residue() {
        let dir = tmp_dir();
        let live = dir.join("live");
        let backup = dir.join("backup");
        write_backup_fixture(&live, "nested/scene.json", b"same");
        write_backup_fixture(&backup, "nested/scene.json", b"same");
        write_backup_fixture(&backup, "old-file.txt", b"residue");

        assert!(!backup_matches_live(&live, &backup).unwrap());
    }

    #[test]
    fn recursive_backup_comparison_reports_missing_or_different_live_files() {
        let dir = tmp_dir();
        let live = dir.join("live");
        let backup = dir.join("backup");
        write_backup_fixture(&live, "project.json", b"newer");
        write_backup_fixture(&backup, "project.json", b"old");

        assert!(!backup_matches_live(&live, &backup).unwrap());
    }

    #[test]
    fn rebuilt_shader_cache_does_not_make_a_backup_stale() {
        let dir = tmp_dir();
        let live = dir.join("live");
        let backup = dir.join("backup");
        write_backup_fixture(&live, "project.json", b"same");
        write_backup_fixture(&backup, "project.json", b"same");
        write_backup_fixture(
            &live,
            "shaders/blobssm40/cache.bin",
            b"live cache",
        );

        assert!(backup_matches_live(&live, &backup).unwrap());
    }

    #[test]
    fn parallel_backup_comparison_omits_unreadable_pairs() {
        let dir = tmp_dir();
        let live = dir.join("live");
        let backup = dir.join("backup");
        write_backup_fixture(&live.join("good"), "project.json", b"same");
        write_backup_fixture(&backup.join("good"), "project.json", b"same");
        std::fs::create_dir_all(live.join("missing")).unwrap();

        let result = compare_backup_folders_blocking(
            live.to_string_lossy().into_owned(),
            backup.to_string_lossy().into_owned(),
            vec!["good".into(), "missing".into()],
            12,
        );

        assert_eq!(result.get("good"), Some(&true));
        assert!(!result.contains_key("missing"));
    }

    #[test]
    fn live_junk_allows_only_dxs_files() {
        let dir = tmp_dir();
        let empty = dir.join("empty");
        let cache = dir.join("cache");
        let project = dir.join("project");
        std::fs::create_dir_all(&empty).unwrap();
        write_backup_fixture(&cache, "nested/cache.DXS", b"cache");
        write_backup_fixture(&project, "project.json", b"project");

        assert!(wallpaper_folder_is_junk(&empty, false).unwrap());
        assert!(wallpaper_folder_is_junk(&cache, false).unwrap());
        assert!(!wallpaper_folder_is_junk(&project, false).unwrap());
    }

    #[test]
    fn rebuilt_shader_tree_is_junk_only_for_backups() {
        let dir = tmp_dir();
        let folder = dir.join("shader-only");
        write_backup_fixture(&folder, "shaders/blobsSM40/cache.bin", b"cache");

        assert!(wallpaper_folder_is_junk(&folder, true).unwrap());
        assert!(!wallpaper_folder_is_junk(&folder, false).unwrap());
    }

    #[test]
    fn parallel_junk_scan_returns_only_junk_folders() {
        let dir = tmp_dir();
        let root = dir.join("root");
        std::fs::create_dir_all(root.join("empty")).unwrap();
        write_backup_fixture(&root.join("cache"), "shader.dxs", b"cache");
        write_backup_fixture(&root.join("normal"), "project.json", b"project");

        let result = find_junk_folders_blocking(
            root.to_string_lossy().into_owned(),
            vec!["empty".into(), "cache".into(), "normal".into(), "missing".into()],
            false,
            4,
        );

        assert!(result.contains(&"empty".to_string()));
        assert!(result.contains(&"cache".to_string()));
        assert!(!result.contains(&"normal".to_string()));
        assert!(!result.contains(&"missing".to_string()));
    }

    #[test]
    fn integrity_reader_batches_entries_and_project_state() {
        let dir = tmp_dir();
        let root = dir.join("library");
        write_backup_fixture(&root.join("good"), "project.json", br#"{"file":"scene.pkg"}"#);
        write_backup_fixture(&root.join("good"), "scene.pkg", b"payload");
        std::fs::create_dir_all(root.join("good").join("materials")).unwrap();
        write_backup_fixture(&root.join("broken"), "project.json", b"{ not valid json");
        write_backup_fixture(&root.join("no-project"), "video.mp4", b"media");

        let result = read_integrity_folders_blocking(
            root.to_string_lossy().into_owned(),
            vec![
                "good".into(),
                "broken".into(),
                "no-project".into(),
                "missing".into(),
            ],
            4,
        );

        let good = result.get("good").unwrap();
        assert!(good.project_present);
        assert_eq!(good.project_json.as_deref(), Some(r#"{"file":"scene.pkg"}"#));
        assert!(good.entries.iter().any(|entry| {
            entry.name == "materials" && entry.is_directory
        }));
        assert!(good.entries.iter().any(|entry| {
            entry.name == "scene.pkg" && !entry.is_directory
        }));

        let broken = result.get("broken").unwrap();
        assert!(broken.project_present);
        assert_eq!(broken.project_json.as_deref(), Some("{ not valid json"));

        let no_project = result.get("no-project").unwrap();
        assert!(!no_project.project_present);
        assert!(no_project.project_json.is_none());
        assert!(!result.contains_key("missing"));
    }

    #[test]
    fn parallel_project_reader_reads_existing_files_and_keeps_raw_json() {
        let dir = tmp_dir();
        let root = dir.join("library");
        write_backup_fixture(&root.join("good"), "project.json", br#"{"title":"Alpha"}"#);
        write_backup_fixture(&root.join("broken"), "project.json", b"{ not valid json");
        std::fs::create_dir_all(root.join("missing")).unwrap();

        let result = read_wallpaper_projects_blocking(
            root.to_string_lossy().into_owned(),
            vec!["good".into(), "broken".into(), "missing".into()],
            4,
        );

        assert_eq!(
            result.get("good").map(|project| project.json.as_str()),
            Some(r#"{"title":"Alpha"}"#),
        );
        assert_eq!(
            result.get("broken").map(|project| project.json.as_str()),
            Some("{ not valid json"),
        );
        assert!(result.get("good").unwrap().changed_micros > 0.0);
        assert!(!result.contains_key("missing"));
    }


    #[test]
    fn myprojects_inventory_keeps_names_and_matches_top_level_version_tokens() {
        let dir = tmp_dir();
        let alpha = dir.join("alpha");
        let empty = dir.join("empty");
        let ignored = dir.join(".werepkg-ex-rescue-old");
        std::fs::create_dir_all(alpha.join("assets")).unwrap();
        std::fs::create_dir_all(&empty).unwrap();
        std::fs::create_dir_all(&ignored).unwrap();
        std::fs::write(alpha.join("z.txt"), b"zz").unwrap();
        std::fs::write(alpha.join("a.txt"), b"a").unwrap();
        std::fs::write(alpha.join("assets").join("nested.txt"), b"ignored").unwrap();
        std::fs::write(dir.join("loose.txt"), b"ignored").unwrap();

        let inventory = my_projects_inventory_blocking(
            dir.to_string_lossy().into_owned(),
            vec![".werepkg-ex-rescue-".to_string()],
            4,
        )
        .unwrap();

        assert_eq!(inventory.len(), 2);
        assert!(inventory.contains_key("alpha"));
        assert_eq!(inventory.get("empty"), Some(&None));
        assert!(!inventory.contains_key(".werepkg-ex-rescue-old"));

        let token = inventory.get("alpha").unwrap().as_ref().unwrap();
        let parts = token.split(';').collect::<Vec<_>>();
        assert_eq!(parts.len(), 2, "nested files must not affect the token");
        assert!(parts[0].starts_with("a.txt|1|"));
        assert!(parts[1].starts_with("z.txt|2|"));
    }

}
