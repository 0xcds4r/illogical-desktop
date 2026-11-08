use std::collections::hash_map::DefaultHasher;
use std::env;
use std::fs;
use std::hash::{Hash, Hasher};
use std::io;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

fn home() -> String {
    env::var("HOME").unwrap_or_else(|_| "/home".into())
}

fn data_home() -> PathBuf {
    match env::var("XDG_DATA_HOME") {
        Ok(value) if !value.is_empty() => PathBuf::from(value),
        _ => PathBuf::from(home()).join(".local/share"),
    }
}

fn cache_home() -> PathBuf {
    match env::var("XDG_CACHE_HOME") {
        Ok(value) if !value.is_empty() => PathBuf::from(value),
        _ => PathBuf::from(home()).join(".cache"),
    }
}

fn trash_dir() -> PathBuf {
    data_home().join("Trash")
}

fn run_capture(command: &str, args: &[&str]) -> Option<String> {
    let output = Command::new(command)
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn mime_of(path: &Path) -> Option<String> {
    run_capture("file", &["--mime-type", "-b", "--", &path.to_string_lossy()])
}

fn percent_encode(input: &str) -> String {
    let mut result = String::new();
    for byte in input.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' | b'/' => {
                result.push(byte as char)
            }
            _ => result.push_str(&format!("%{byte:02X}")),
        }
    }
    result
}

fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            if let Ok(value) = u8::from_str_radix(&input[index + 1..index + 3], 16) {
                out.push(value);
                index += 3;
                continue;
            }
        }
        out.push(bytes[index]);
        index += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

fn copy_recursive(source: &Path, destination: &Path) -> io::Result<()> {
    let metadata = fs::symlink_metadata(source)?;
    if metadata.file_type().is_symlink() {
        #[cfg(unix)]
        {
            let target = fs::read_link(source)?;
            std::os::unix::fs::symlink(target, destination)?;
            return Ok(());
        }
        #[cfg(not(unix))]
        {
            fs::copy(source, destination)?;
            return Ok(());
        }
    }
    if metadata.is_dir() {
        fs::create_dir_all(destination)?;
        for entry in fs::read_dir(source)? {
            let entry = entry?;
            copy_recursive(&entry.path(), &destination.join(entry.file_name()))?;
        }
        return Ok(());
    }
    fs::copy(source, destination)?;
    Ok(())
}

fn move_path(source: &Path, destination: &Path) -> io::Result<()> {
    match fs::rename(source, destination) {
        Ok(()) => Ok(()),
        Err(error) if error.raw_os_error() == Some(18) => {
            copy_recursive(source, destination)?;
            remove_any(source);
            Ok(())
        }
        Err(error) => Err(error),
    }
}

fn unique_destination(directory: &Path, name: &str) -> PathBuf {
    let mut candidate = directory.join(name);
    if fs::symlink_metadata(&candidate).is_err() {
        return candidate;
    }
    let mut counter = 2;
    loop {
        candidate = directory.join(format!("{name}.{counter}"));
        if fs::symlink_metadata(&candidate).is_err() {
            return candidate;
        }
        counter += 1;
    }
}

fn ensure_trash() -> io::Result<(PathBuf, PathBuf)> {
    let files = trash_dir().join("files");
    let info = trash_dir().join("info");
    fs::create_dir_all(&files)?;
    fs::create_dir_all(&info)?;
    Ok((files, info))
}

fn trash_move(paths: &[String]) -> io::Result<()> {
    let (files, info) = ensure_trash()?;
    for raw in paths {
        let source = if Path::new(raw).is_absolute() {
            PathBuf::from(raw)
        } else {
            env::current_dir()?.join(raw)
        };
        if fs::symlink_metadata(&source).is_err() {
            continue;
        }
        let name = source
            .file_name()
            .map(|value| value.to_string_lossy().to_string())
            .unwrap_or_else(|| "file".into());
        let destination = unique_destination(&files, &name);
        move_path(&source, &destination)?;
        let info_name = destination
            .file_name()
            .map(|value| value.to_string_lossy().to_string())
            .unwrap_or(name);
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let info_path = info.join(format!("{info_name}.trashinfo"));
        let contents = format!(
            "[Trash Info]\nPath={}\nDeletionDate={}\n",
            percent_encode(&source.to_string_lossy()),
            format_date(now)
        );
        fs::write(info_path, contents)?;
    }
    Ok(())
}

fn format_date(seconds: u64) -> String {
    run_capture("date", &["-d", &format!("@{seconds}"), "+%Y-%m-%dT%H:%M:%S"])
        .unwrap_or_else(|| format!("{seconds}"))
}

fn trash_restore(original_paths: &[String]) -> io::Result<()> {
    let (files, info) = ensure_trash()?;
    let targets: Vec<String> = original_paths.iter().map(|p| p.to_string()).collect();
    let mut entries: Vec<(PathBuf, PathBuf, String)> = Vec::new();
    for entry in fs::read_dir(&info)? {
        let entry = match entry {
            Ok(value) => value,
            Err(_) => continue,
        };
        let info_path = entry.path();
        if info_path.extension().and_then(|v| v.to_str()) != Some("trashinfo") {
            continue;
        }
        let contents = match fs::read_to_string(&info_path) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let original = contents.lines().find_map(|line| {
            line.strip_prefix("Path=")
                .map(|value| percent_decode(value.trim()))
        });
        if let Some(original) = original {
            let name = info_path
                .file_name()
                .map(|value| value.to_string_lossy().to_string())
                .unwrap_or_default();
            let stem = name.trim_end_matches(".trashinfo");
            entries.push((info_path, files.join(stem), original));
        }
    }
    entries.sort_by_key(|(info_path, _, _)| {
        fs::metadata(info_path)
            .and_then(|meta| meta.modified())
            .ok()
    });
    entries.reverse();
    for (info_path, trashed, original) in entries {
        if !targets.contains(&original) {
            continue;
        }
        if fs::symlink_metadata(&trashed).is_err() {
            continue;
        }
        let destination = unique_destination(
            Path::new(&original).parent().unwrap_or(Path::new("/")),
            Path::new(&original)
                .file_name()
                .map(|value| value.to_string_lossy().to_string())
                .unwrap_or_else(|| "file".into())
                .as_str(),
        );
        if let Some(parent) = destination.parent() {
            let _ = fs::create_dir_all(parent);
        }
        move_path(&trashed, &destination)?;
        let _ = fs::remove_file(info_path);
    }
    Ok(())
}

fn remove_any(path: &Path) {
    if let Ok(meta) = fs::symlink_metadata(path) {
        if meta.is_dir() && !meta.file_type().is_symlink() {
            let _ = fs::remove_dir_all(path);
        } else {
            let _ = fs::remove_file(path);
        }
    }
}

fn trash_empty() -> io::Result<()> {
    let (files, info) = ensure_trash()?;
    for entry in fs::read_dir(&files)? {
        if let Ok(entry) = entry {
            remove_any(&entry.path());
        }
    }
    for entry in fs::read_dir(&info)? {
        if let Ok(entry) = entry {
            let _ = fs::remove_file(entry.path());
        }
    }
    Ok(())
}

fn find_desktop_file(id: &str) -> Option<PathBuf> {
    let home = home();
    let candidates = [
        format!("{home}/.local/share/applications/{id}"),
        format!("/usr/share/applications/{id}"),
        format!("/var/lib/flatpak/exports/share/applications/{id}"),
        format!("{home}/.local/share/flatpak/exports/share/applications/{id}"),
    ];
    candidates
        .iter()
        .map(PathBuf::from)
        .find(|path| path.is_file())
}

fn desktop_value(path: &Path, key: &str) -> String {
    let contents = fs::read_to_string(path).unwrap_or_default();
    let prefix = format!("{key}=");
    contents
        .lines()
        .find_map(|line| line.strip_prefix(prefix.as_str()))
        .unwrap_or("")
        .to_string()
}

fn default_app_id(mime: &str) -> Option<String> {
    let id = run_capture("xdg-mime", &["query", "default", mime])?;
    if id.ends_with(".desktop") {
        Some(id)
    } else {
        None
    }
}

fn app_icon(id: &str) -> Option<String> {
    let path = find_desktop_file(id)?;
    let icon = desktop_value(&path, "Icon");
    if icon.is_empty() {
        None
    } else {
        Some(icon)
    }
}

fn file_icon(path: &Path) -> io::Result<()> {
    let mime = mime_of(path).unwrap_or_else(|| "application/octet-stream".into());
    let metadata = fs::symlink_metadata(path).ok();
    let mut flags: Vec<&str> = Vec::new();
    if let Some(meta) = &metadata {
        if meta.file_type().is_symlink() {
            flags.push("link");
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = meta.permissions().mode();
            if meta.is_file() && mode & 0o111 != 0 {
                flags.push("exec");
            }
            if mode & 0o200 == 0 {
                flags.push("readonly");
            }
        }
    }
    let flags = flags.join(",");

    if mime.starts_with("image/") {
        println!("thumb\t\t{flags}");
        return Ok(());
    }

    if mime.starts_with("video/") {
        if let Some(thumb) = make_thumbnail(path, "video") {
            println!("filethumb\t{}\t{flags}", thumb);
            return Ok(());
        }
    } else if mime == "application/pdf" {
        if let Some(thumb) = make_thumbnail(path, "pdf") {
            println!("filethumb\t{}\t{flags}", thumb);
            return Ok(());
        }
    }

    let lookup_mime = if mime == "inode/x-empty" {
        "text/plain"
    } else {
        mime.as_str()
    };

    if let Some(id) = default_app_id(lookup_mime) {
        if let Some(icon) = app_icon(&id) {
            if icon.starts_with('/') {
                println!("path\t{icon}\t{flags}");
            } else {
                println!("name\t{icon}\t{flags}");
            }
            return Ok(());
        }
    }

    println!("name\t{}\t{flags}", mime.replace('/', "-"));
    Ok(())
}

fn make_thumbnail(path: &Path, kind: &str) -> Option<String> {
    let directory = cache_home().join("quickshell/media/desktop-thumbs");
    let _ = fs::create_dir_all(&directory);
    let modified = fs::metadata(path)
        .and_then(|meta| meta.modified())
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_secs())
        .unwrap_or(0);
    let mut hasher = DefaultHasher::new();
    path.to_string_lossy().hash(&mut hasher);
    modified.hash(&mut hasher);
    kind.hash(&mut hasher);
    let output = directory.join(format!("{:016x}.png", hasher.finish()));
    if output.is_file() && fs::metadata(&output).map(|m| m.len() > 0).unwrap_or(false) {
        return Some(output.to_string_lossy().to_string());
    }
    let status = if kind == "video" {
        Command::new("ffmpeg")
            .args([
                "-y",
                "-loglevel",
                "error",
                "-ss",
                "1",
                "-i",
                &path.to_string_lossy(),
                "-frames:v",
                "1",
                "-vf",
                "scale=256:-2",
                "-an",
                &output.to_string_lossy(),
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .ok()
    } else {
        let prefix = output.with_extension("");
        Command::new("pdftoppm")
            .args([
                "-f",
                "1",
                "-l",
                "1",
                "-singlefile",
                "-png",
                "-scale-to",
                "256",
                &path.to_string_lossy(),
                &prefix.to_string_lossy(),
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .ok()
    };
    if status.map(|s| s.success()).unwrap_or(false) && output.is_file() {
        Some(output.to_string_lossy().to_string())
    } else {
        None
    }
}

fn open_path(path: &str) -> io::Result<()> {
    let mime = mime_of(Path::new(path)).unwrap_or_else(|| "application/octet-stream".into());
    if let Some(id) = default_app_id(&mime) {
        if let Some(desktop_file) = find_desktop_file(&id) {
            let status = Command::new("gio")
                .args([
                    "launch",
                    &desktop_file.to_string_lossy(),
                    path,
                ])
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
            if status.map(|s| s.success()).unwrap_or(false) {
                return Ok(());
            }
        }
    }
    let _ = Command::new("gio")
        .args(["open", path])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    Ok(())
}

fn open_with(path: &str) -> io::Result<()> {
    let mime = match mime_of(Path::new(path)) {
        Some(value) => value,
        None => return Ok(()),
    };
    let output = match run_capture("gio", &["mime", &mime]) {
        Some(value) => value,
        None => return Ok(()),
    };
    let mut seen = std::collections::HashSet::new();
    for line in output.lines() {
        let id = line.trim();
        if !id.ends_with(".desktop") || !seen.insert(id.to_string()) {
            continue;
        }
        let desktop_file = match find_desktop_file(id) {
            Some(value) => value,
            None => continue,
        };
        let name = desktop_value(&desktop_file, "Name");
        let icon = desktop_value(&desktop_file, "Icon");
        println!(
            "{}\t{}\t{}\t{}",
            id,
            name,
            icon,
            desktop_file.to_string_lossy()
        );
    }
    Ok(())
}

fn open_trash() -> io::Result<()> {
    let default_manager = run_capture("xdg-mime", &["query", "default", "inode/directory"])
        .unwrap_or_default();
    let managers: [(&str, &str, &str); 3] = [
        ("dolphin", "trash:/", "*dolphin*"),
        ("nautilus", "trash://", "*nautilus*"),
        ("thunar", "trash://", "*thunar*"),
    ];
    for (binary, uri, pattern) in managers {
        if default_manager.contains(pattern.trim_matches('*')) && command_exists(binary) {
            let _ = Command::new(binary)
                .arg(uri)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn();
            return Ok(());
        }
    }
    for (binary, uri, _) in managers {
        if command_exists(binary) {
            let _ = Command::new(binary)
                .arg(uri)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn();
            return Ok(());
        }
    }
    let _ = Command::new("gio")
        .args(["open", "trash://"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    Ok(())
}

fn command_exists(binary: &str) -> bool {
    env::var("PATH")
        .unwrap_or_default()
        .split(':')
        .map(|dir| Path::new(dir).join(binary))
        .any(|candidate| candidate.is_file())
}

fn human_size(bytes: u64) -> String {
    let units = ["B", "K", "M", "G", "T", "P"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit + 1 < units.len() {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes} B")
    } else {
        format!("{value:.1}{}", units[unit])
    }
}

fn properties(path: &str) -> io::Result<()> {
    let target = Path::new(path);
    let metadata = match fs::symlink_metadata(target) {
        Ok(value) => value,
        Err(_) => {
            println!("Name\t—");
            println!("Path\t{path}");
            return Ok(());
        }
    };
    let name = target
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| path.to_string());
    println!("Name\t{name}");
    println!("Path\t{path}");

    if metadata.file_type().is_symlink() {
        println!("Type\tSymbolic link");
        if let Ok(destination) = fs::read_link(target) {
            println!("Target\t{}", destination.to_string_lossy());
        }
    } else if metadata.is_dir() {
        println!("Type\tFolder");
    } else {
        println!("Type\tFile");
    }

    if let Some(mime) = mime_of(target) {
        println!("MIME\t{mime}");
    }

    if metadata.is_dir() {
        if let Some(size) = run_capture("du", &["-sh", "--", path]) {
            if let Some(first) = size.split_whitespace().next() {
                println!("Size\t{first}");
            }
        }
    } else {
        let bytes = metadata.len();
        println!("Size\t{} ({bytes} bytes)", human_size(bytes));
    }

    if let Some(modified) = run_capture("stat", &["-c", "%y", "--", path]) {
        let value = modified.split('.').next().unwrap_or(&modified);
        println!("Modified\t{value}");
    }
    if let Some(permissions) = run_capture("stat", &["-c", "%A (%a)", "--", path]) {
        println!("Permissions\t{permissions}");
    }
    if let Some(owner) = run_capture("stat", &["-c", "%U:%G", "--", path]) {
        println!("Owner\t{owner}");
    }
    Ok(())
}

fn compress(arguments: &[String]) -> io::Result<()> {
    if arguments.len() < 5 {
        return Ok(());
    }
    let destination = &arguments[0];
    let parent = &arguments[1];
    let format = &arguments[2];
    let level = &arguments[3];
    let names = &arguments[4..];
    let mut command;
    if format == "targz" {
        command = Command::new("tar");
        command.args([
            "-I",
            &format!("gzip -{level}"),
            "-cf",
            destination,
            "-C",
            parent,
        ]);
    } else {
        command = Command::new("zip");
        command
            .current_dir(parent)
            .args(["-r", &format!("-{level}"), destination, "--"]);
    }
    for name in names {
        command.arg(name);
    }
    let _ = command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    Ok(())
}

#[cfg(unix)]
extern "C" {
    fn signal(signal: i32, handler: usize) -> usize;
}


fn desktop_dirs() -> Vec<PathBuf> {
    let home = home();
    vec![
        PathBuf::from(format!("{home}/.local/share/applications")),
        PathBuf::from("/usr/share/applications"),
        PathBuf::from("/var/lib/flatpak/exports/share/applications"),
        PathBuf::from(format!("{home}/.local/share/flatpak/exports/share/applications")),
    ]
}

fn parse_desktop_entry(path: &Path) -> Option<(String, String)> {
    let contents = fs::read_to_string(path).ok()?;
    let mut in_entry = false;
    let mut name = String::new();
    let mut icon = String::new();
    let mut kind = String::new();
    let mut hidden = false;
    for line in contents.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_entry {
            continue;
        }
        if let Some(value) = line.strip_prefix("Name=") {
            if name.is_empty() {
                name = value.to_string();
            }
        } else if let Some(value) = line.strip_prefix("Icon=") {
            if icon.is_empty() {
                icon = value.to_string();
            }
        } else if let Some(value) = line.strip_prefix("Type=") {
            kind = value.to_string();
        } else if line == "NoDisplay=true" || line == "Hidden=true" {
            hidden = true;
        }
    }
    if kind != "Application" || hidden || name.is_empty() {
        None
    } else {
        Some((name, icon))
    }
}

fn list_apps() {
    let mut seen = std::collections::HashSet::new();
    let mut entries: Vec<(String, String, String, String)> = Vec::new();
    for directory in desktop_dirs() {
        let iterator = match fs::read_dir(&directory) {
            Ok(value) => value,
            Err(_) => continue,
        };
        for entry in iterator.flatten() {
            let path = entry.path();
            if path.extension().and_then(|value| value.to_str()) != Some("desktop") {
                continue;
            }
            let id = match path.file_name() {
                Some(value) => value.to_string_lossy().to_string(),
                None => continue,
            };
            if !seen.insert(id.clone()) {
                continue;
            }
            if let Some((name, icon)) = parse_desktop_entry(&path) {
                entries.push((id, name, icon, path.to_string_lossy().to_string()));
            }
        }
    }
    entries.sort_by(|a, b| a.1.to_lowercase().cmp(&b.1.to_lowercase()));
    for (id, name, icon, path) in entries {
        println!("{id}\t{name}\t{icon}\t{path}");
    }
}

fn unique_shortcut(directory: &Path, name: &str) -> PathBuf {
    let mut candidate = directory.join(name);
    if fs::symlink_metadata(&candidate).is_err() {
        return candidate;
    }
    let path = Path::new(name);
    let stem = path
        .file_stem()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| name.to_string());
    let extension = path
        .extension()
        .map(|value| format!(".{}", value.to_string_lossy()))
        .unwrap_or_default();
    let mut counter = 2;
    loop {
        candidate = directory.join(format!("{stem} ({counter}){extension}"));
        if fs::symlink_metadata(&candidate).is_err() {
            return candidate;
        }
        counter += 1;
    }
}

fn create_shortcut(source: &str, directory: &str) -> io::Result<()> {
    let source_path = Path::new(source);
    let name = source_path
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "invalid shortcut path"))?;
    let target = unique_shortcut(Path::new(directory), &name);
    fs::copy(source_path, &target)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&target, fs::Permissions::from_mode(0o755));
    }
    println!("{}", target.to_string_lossy());
    Ok(())
}

fn main() {
    // Behave like normal CLI tools when the reader closes the pipe.
    #[cfg(unix)]
    unsafe {
        signal(13, 0); // SIGPIPE, SIG_DFL
    }
    let arguments: Vec<String> = env::args().skip(1).collect();
    if arguments.is_empty() {
        eprintln!("usage: desktop-helper <trash|icon|open|open-with|open-trash|props|compress> ...");
        std::process::exit(2);
    }
    let command = arguments[0].as_str();
    let rest = &arguments[1..];
    let result = match command {
        "trash" => match rest.first().map(|value| value.as_str()) {
            Some("move") => trash_move(&rest[1..]),
            Some("restore") => trash_restore(&rest[1..]),
            Some("empty") => trash_empty(),
            Some("count") => {
                let count = ensure_trash()
                    .and_then(|(files, _)| fs::read_dir(files))
                    .map(|entries| entries.count())
                    .unwrap_or(0);
                println!("{count}");
                Ok(())
            }
            _ => Ok(()),
        },
        "icon" => match rest.first() {
            Some(path) => file_icon(Path::new(path)),
            None => Ok(()),
        },
        "open" => match rest.first() {
            Some(path) => open_path(path),
            None => Ok(()),
        },
        "open-with" => match rest.first() {
            Some(path) => open_with(path),
            None => Ok(()),
        },
        "open-trash" => open_trash(),
        "props" => match rest.first() {
            Some(path) => properties(path),
            None => Ok(()),
        },
        "compress" => compress(rest),
        "apps" => {
            list_apps();
            Ok(())
        }
        "shortcut" => {
            if rest.len() >= 2 {
                create_shortcut(&rest[0], &rest[1])
            } else {
                Ok(())
            }
        }
        _ => {
            eprintln!("unknown command: {command}");
            std::process::exit(2);
        }
    };
    if let Err(error) = result {
        eprintln!("{command}: {error}");
        std::process::exit(1);
    }
}
