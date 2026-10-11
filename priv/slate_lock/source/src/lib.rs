use rustler::{Encoder, Env, Resource, ResourceArc, Term};
use std::collections::HashMap;
use std::fs::{self, File, OpenOptions, TryLockError};
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

mod atoms {
    rustler::atoms! {
        busy, unsafe_alias, unsupported_filesystem, os_failure,
        file_error_context, some, nil,
    }
}

static NEXT_ID: AtomicU64 = AtomicU64::new(1);
// The registry, not Erlang resource GC, owns live files. Lost tokens fail closed.
static LOCKS: OnceLock<Mutex<HashMap<u64, File>>> = OnceLock::new();

struct LockToken {
    id: u64,
}

#[rustler::resource_impl]
impl Resource for LockToken {}

#[derive(Debug)]
enum LockError {
    Busy,
    UnsafeAlias(PathBuf, String),
    UnsupportedFilesystem(PathBuf),
    OsFailure(PathBuf, String),
}

impl Encoder for LockError {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let (kind, path, reason) = match self {
            Self::Busy => return atoms::busy().encode(env),
            Self::UnsafeAlias(path, reason) => (atoms::unsafe_alias(), path, reason.as_str()),
            Self::UnsupportedFilesystem(path) => (
                atoms::unsupported_filesystem(),
                path,
                "unqualified_filesystem",
            ),
            Self::OsFailure(path, reason) => (atoms::os_failure(), path, reason.as_str()),
        };
        let path_text = path.to_string_lossy();
        let context = (
            atoms::file_error_context(),
            (atoms::some(), path_text.as_ref()),
            reason,
        );
        (kind, context).encode(env)
    }
}

fn os_failure(path: &Path, error: io::Error) -> LockError {
    LockError::OsFailure(path.to_owned(), error.to_string())
}

fn canonical_path(path: &Path) -> Result<PathBuf, LockError> {
    match fs::canonicalize(path) {
        Ok(path) => Ok(path),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            match fs::symlink_metadata(path) {
                Ok(metadata) if metadata.file_type().is_symlink() => {
                    return Err(LockError::UnsafeAlias(
                        path.to_owned(),
                        "dangling_symlink".into(),
                    ));
                }
                Ok(_) => {}
                Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                Err(error) => return Err(os_failure(path, error)),
            }
            let parent = path
                .parent()
                .filter(|p| !p.as_os_str().is_empty())
                .unwrap_or(Path::new("."));
            let parent = fs::canonicalize(parent).map_err(|error| os_failure(parent, error))?;
            let leaf = path.file_name().ok_or_else(|| {
                LockError::UnsafeAlias(path.to_owned(), "missing_filename".into())
            })?;
            Ok(parent.join(leaf))
        }
        Err(error) => Err(os_failure(path, error)),
    }
}

#[cfg(unix)]
fn link_count(file: &File) -> io::Result<u64> {
    use std::os::unix::fs::MetadataExt;
    Ok(file.metadata()?.nlink())
}

#[cfg(windows)]
fn link_count(file: &File) -> io::Result<u64> {
    use std::os::windows::io::AsRawHandle;
    use windows_sys::Win32::Storage::FileSystem::{
        GetFileInformationByHandle, BY_HANDLE_FILE_INFORMATION,
    };
    let mut info: BY_HANDLE_FILE_INFORMATION = unsafe { std::mem::zeroed() };
    // The handle is borrowed from a live File and info is writable for this call.
    if unsafe { GetFileInformationByHandle(file.as_raw_handle(), &mut info) } == 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(u64::from(info.nNumberOfLinks))
}

fn validate_data(path: &Path) -> Result<(), LockError> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            if unsafe_file(&metadata) {
                return Err(LockError::UnsafeAlias(
                    path.to_owned(),
                    "data_is_not_regular".into(),
                ));
            }
            let file = File::open(path).map_err(|error| os_failure(path, error))?;
            if link_count(&file).map_err(|error| os_failure(path, error))? != 1 {
                return Err(LockError::UnsafeAlias(
                    path.to_owned(),
                    "data_hard_link".into(),
                ));
            }
            validate_file_location(path, &file, "data_file_mount")?;
            Ok(())
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(os_failure(path, error)),
    }
}

#[cfg(target_os = "linux")]
fn validate_file_location(path: &Path, file: &File, mount_reason: &str) -> Result<(), LockError> {
    let status = rustix::fs::fstatfs(file).map_err(|error| os_failure(path, error.into()))?;
    if !qualified_linux_filesystem(&status) {
        return Err(LockError::UnsupportedFilesystem(path.to_owned()));
    }
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let directory = rustix::fs::open(
        parent,
        rustix::fs::OFlags::PATH | rustix::fs::OFlags::DIRECTORY | rustix::fs::OFlags::CLOEXEC,
        rustix::fs::Mode::empty(),
    )
    .map_err(|error| os_failure(parent, error.into()))?;
    if mount_id(file, path)? != mount_id(&directory, parent)? {
        return Err(LockError::UnsafeAlias(path.to_owned(), mount_reason.into()));
    }
    Ok(())
}

#[cfg(target_os = "linux")]
fn mount_id(file: &impl std::os::fd::AsFd, path: &Path) -> Result<u64, LockError> {
    use rustix::fs::{statx, AtFlags, StatxFlags};
    let status = statx(file, "", AtFlags::EMPTY_PATH, StatxFlags::MNT_ID)
        .map_err(|error| os_failure(path, error.into()))?;
    if status.stx_mask & StatxFlags::MNT_ID.bits() == 0 {
        return Err(LockError::UnsupportedFilesystem(path.to_owned()));
    }
    Ok(status.stx_mnt_id)
}

#[cfg(not(target_os = "linux"))]
fn validate_file_location(path: &Path, _file: &File, _mount_reason: &str) -> Result<(), LockError> {
    if supported_filesystem(path)? {
        Ok(())
    } else {
        Err(LockError::UnsupportedFilesystem(path.to_owned()))
    }
}

fn unsafe_file(metadata: &fs::Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        use windows_sys::Win32::Storage::FileSystem::FILE_ATTRIBUTE_REPARSE_POINT;
        if metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
            return true;
        }
    }
    !metadata.is_file() || metadata.file_type().is_symlink()
}

#[cfg(target_os = "linux")]
fn supported_filesystem(parent: &Path) -> Result<bool, LockError> {
    let status = rustix::fs::statfs(parent).map_err(|error| os_failure(parent, error.into()))?;
    Ok(qualified_linux_filesystem(&status))
}

#[cfg(target_os = "linux")]
fn qualified_linux_filesystem(status: &rustix::fs::StatFs) -> bool {
    status.f_type == 0xef53 || status.f_type == 0x01021994
}

#[cfg(target_os = "macos")]
fn supported_filesystem(parent: &Path) -> Result<bool, LockError> {
    let status = rustix::fs::statfs(parent).map_err(|error| os_failure(parent, error.into()))?;
    Ok(status
        .f_fstypename
        .iter()
        .map(|c| *c as u8)
        .take_while(|c| *c != 0)
        .eq(b"apfs".iter().copied()))
}

#[cfg(windows)]
fn supported_filesystem(parent: &Path) -> Result<bool, LockError> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{
        GetDriveTypeW, GetVolumeInformationW, GetVolumePathNameW,
    };
    use windows_sys::Win32::System::WindowsProgramming::DRIVE_FIXED;
    let path: Vec<u16> = parent.as_os_str().encode_wide().chain(Some(0)).collect();
    let mut volume = vec![0u16; 32768];
    let mut filesystem = vec![0u16; 256];
    // All pointers refer to valid NUL-terminated input or sized writable buffers.
    unsafe {
        if GetVolumePathNameW(path.as_ptr(), volume.as_mut_ptr(), volume.len() as u32) == 0 {
            return Err(os_failure(parent, io::Error::last_os_error()));
        }
        if GetDriveTypeW(volume.as_ptr()) != DRIVE_FIXED {
            return Ok(false);
        }
        if GetVolumeInformationW(
            volume.as_ptr(),
            std::ptr::null_mut(),
            0,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            filesystem.as_mut_ptr(),
            filesystem.len() as u32,
        ) == 0
        {
            return Err(os_failure(parent, io::Error::last_os_error()));
        }
    }
    Ok(filesystem
        .iter()
        .copied()
        .take_while(|c| *c != 0)
        .eq("NTFS".encode_utf16()))
}

#[cfg(not(any(target_os = "linux", target_os = "macos", windows)))]
fn supported_filesystem(_parent: &Path) -> Result<bool, LockError> {
    Ok(false)
}

fn open_sidecar(path: &Path) -> Result<File, LockError> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if unsafe_file(&metadata) => {
            return Err(LockError::UnsafeAlias(
                path.to_owned(),
                "unsafe_sidecar".into(),
            ));
        }
        Ok(_) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(os_failure(path, error)),
    }
    let mut options = OpenOptions::new();
    options.read(true).write(true).create(true).truncate(false);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        let flags = rustix::fs::OFlags::NOFOLLOW
            | rustix::fs::OFlags::CLOEXEC
            | rustix::fs::OFlags::NONBLOCK;
        options.mode(0o600).custom_flags(flags.bits() as i32);
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        use windows_sys::Win32::Storage::FileSystem::{
            FILE_FLAG_OPEN_REPARSE_POINT, FILE_SHARE_READ, FILE_SHARE_WRITE,
        };
        options
            .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
            .share_mode(FILE_SHARE_READ | FILE_SHARE_WRITE);
    }
    let file = options
        .open(path)
        .map_err(|error| os_failure(path, error))?;
    let named = fs::symlink_metadata(path).map_err(|error| os_failure(path, error))?;
    if unsafe_file(&named) || link_count(&file).map_err(|error| os_failure(path, error))? != 1 {
        return Err(LockError::UnsafeAlias(
            path.to_owned(),
            "unsafe_sidecar".into(),
        ));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let opened = file.metadata().map_err(|error| os_failure(path, error))?;
        if opened.dev() != named.dev() || opened.ino() != named.ino() {
            return Err(LockError::UnsafeAlias(
                path.to_owned(),
                "sidecar_changed".into(),
            ));
        }
    }
    validate_file_location(path, &file, "sidecar_file_mount")?;
    Ok(file)
}

#[rustler::nif(schedule = "DirtyIo")]
fn resolve(path: String) -> Result<String, LockError> {
    let canonical = canonical_path(Path::new(&path))?;
    canonical
        .to_str()
        .map(str::to_owned)
        .ok_or_else(|| LockError::UnsafeAlias(canonical.clone(), "path_is_not_utf8".into()))
}

#[rustler::nif(schedule = "DirtyIo")]
fn acquire(path: String) -> Result<(ResourceArc<LockToken>, String), LockError> {
    let original = Path::new(&path);
    let canonical = canonical_path(original)?;
    validate_data(&canonical)?;
    let parent = canonical
        .parent()
        .ok_or_else(|| LockError::UnsafeAlias(canonical.clone(), "missing_parent".into()))?;
    if !supported_filesystem(parent)? {
        return Err(LockError::UnsupportedFilesystem(canonical));
    }
    let mut sidecar = canonical.as_os_str().to_owned();
    sidecar.push(".slate.lock");
    let sidecar = PathBuf::from(sidecar);
    let file = open_sidecar(&sidecar)?;
    match file.try_lock() {
        Ok(()) => {}
        Err(TryLockError::WouldBlock) => return Err(LockError::Busy),
        Err(TryLockError::Error(error)) => return Err(os_failure(&sidecar, error)),
    }
    if canonical_path(original)? != canonical {
        return Err(LockError::UnsafeAlias(canonical, "path_changed".into()));
    }
    validate_data(&canonical)?;
    let canonical_text = canonical
        .to_str()
        .ok_or_else(|| LockError::UnsafeAlias(canonical.clone(), "path_is_not_utf8".into()))?
        .to_owned();
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    let mut locks = LOCKS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .map_err(|error| LockError::OsFailure(sidecar, error.to_string()))?;
    locks.insert(id, file);
    Ok((ResourceArc::new(LockToken { id }), canonical_text))
}

#[rustler::nif(schedule = "DirtyIo")]
fn release(token: ResourceArc<LockToken>) -> Result<rustler::Atom, LockError> {
    let mut locks = LOCKS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .map_err(|error| LockError::OsFailure(PathBuf::new(), error.to_string()))?;
    let file = locks
        .get(&token.id)
        .ok_or_else(|| LockError::OsFailure(PathBuf::new(), "lock_already_released".into()))?;
    file.unlock()
        .map_err(|error| os_failure(Path::new(""), error))?;
    locks.remove(&token.id);
    Ok(atoms::nil())
}

rustler::init!("slate_lock_nif");

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    static NEXT_DIRECTORY: AtomicU64 = AtomicU64::new(0);

    struct Directory(PathBuf);

    impl Directory {
        fn new() -> Self {
            let stamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let sequence = NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "slate-lock-{}-{stamp}-{sequence}",
                std::process::id()
            ));
            fs::create_dir(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for Directory {
        fn drop(&mut self) {
            fs::remove_dir_all(&self.0).unwrap();
        }
    }

    #[test]
    fn immediate_contention_and_close_release() {
        let directory = Directory::new();
        let path = directory.0.join("data.slate.lock");
        let first = open_sidecar(&path).unwrap();
        let second = open_sidecar(&path).unwrap();
        first.try_lock().unwrap();
        assert!(matches!(second.try_lock(), Err(TryLockError::WouldBlock)));
        drop(first);
        second.try_lock().unwrap();
        second.unlock().unwrap();
        assert!(path.is_file());
    }

    #[test]
    fn reject_hard_linked_data_and_sidecars() {
        let directory = Directory::new();
        let data = directory.0.join("data");
        let alias = directory.0.join("alias");
        fs::write(&data, []).unwrap();
        fs::hard_link(&data, &alias).unwrap();
        assert!(matches!(
            validate_data(&data),
            Err(LockError::UnsafeAlias(_, _))
        ));
        assert!(matches!(
            open_sidecar(&alias),
            Err(LockError::UnsafeAlias(_, _))
        ));
    }

    #[test]
    fn reject_nonregular_sidecars() {
        let directory = Directory::new();
        assert!(matches!(
            open_sidecar(&directory.0),
            Err(LockError::UnsafeAlias(_, _))
        ));
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn reject_data_on_unsupported_filesystem() {
        let path = Path::new("/proc/version");
        assert!(matches!(
            validate_data(path),
            Err(LockError::UnsupportedFilesystem(_))
        ));
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn accept_data_without_directory_listing_permission() {
        use std::os::unix::fs::PermissionsExt;
        let directory = Directory::new();
        let data = directory.0.join("data");
        fs::write(&data, []).unwrap();
        fs::set_permissions(&directory.0, fs::Permissions::from_mode(0o300)).unwrap();
        let result = validate_data(&data);
        fs::set_permissions(&directory.0, fs::Permissions::from_mode(0o700)).unwrap();
        result.unwrap();
    }

    #[cfg(target_os = "linux")]
    struct FileMount(PathBuf);

    #[cfg(target_os = "linux")]
    impl FileMount {
        fn new(source: &Path, destination: &Path) -> Self {
            assert_eq!(
                std::env::var("SLATE_PRIVATE_MOUNT_NAMESPACE").as_deref(),
                Ok("1"),
                "run mounted-file tests inside a private mount namespace"
            );
            fs::write(destination, []).unwrap();
            assert!(std::process::Command::new("mount")
                .arg("--bind")
                .arg(source)
                .arg(destination)
                .status()
                .unwrap()
                .success());
            Self(destination.to_owned())
        }
    }

    #[cfg(target_os = "linux")]
    impl Drop for FileMount {
        fn drop(&mut self) {
            assert!(std::process::Command::new("umount")
                .arg(&self.0)
                .status()
                .unwrap()
                .success());
        }
    }

    #[cfg(target_os = "linux")]
    #[test]
    #[ignore = "requires a private mount namespace; run by Linux native CI"]
    fn reject_file_bind_mount_aliases() {
        let directory = Directory::new();
        let data = directory.0.join("data");
        fs::write(&data, []).unwrap();
        let first = FileMount::new(&data, &directory.0.join("first"));
        let second = FileMount::new(&data, &directory.0.join("second"));
        validate_data(&data).unwrap();
        for alias in [&first.0, &second.0] {
            assert!(matches!(
                validate_data(alias),
                Err(LockError::UnsafeAlias(_, reason)) if reason == "data_file_mount"
            ));
        }
        assert!(matches!(
            open_sidecar(&first.0),
            Err(LockError::UnsafeAlias(_, reason)) if reason == "sidecar_file_mount"
        ));
    }

    #[cfg(target_os = "linux")]
    #[test]
    #[ignore = "requires a private mount namespace; run by Linux native CI"]
    fn reject_unsupported_file_mounted_into_supported_directory() {
        let directory = Directory::new();
        assert!(supported_filesystem(&directory.0).unwrap());
        let mounted = FileMount::new(Path::new("/proc/version"), &directory.0.join("data"));
        assert!(matches!(
            validate_data(&mounted.0),
            Err(LockError::UnsupportedFilesystem(_))
        ));
    }

    #[cfg(unix)]
    #[test]
    fn resolve_symlinks_before_parent_segments() {
        use std::os::unix::fs::symlink;
        let directory = Directory::new();
        let real = directory.0.join("real");
        fs::create_dir(&real).unwrap();
        fs::create_dir(real.join("nested")).unwrap();
        let alias = directory.0.join("alias");
        symlink(real.join("nested"), &alias).unwrap();
        assert_eq!(
            canonical_path(&alias.join("../new")).unwrap(),
            fs::canonicalize(&real).unwrap().join("new")
        );
        let existing = real.join("existing");
        fs::write(&existing, []).unwrap();
        symlink(&existing, directory.0.join("file-alias")).unwrap();
        assert_eq!(
            canonical_path(&directory.0.join("file-alias")).unwrap(),
            fs::canonicalize(&existing).unwrap()
        );
    }

    #[cfg(unix)]
    #[test]
    fn reject_symlinked_sidecars_and_dangling_data() {
        use std::os::unix::fs::symlink;
        let directory = Directory::new();
        let target = directory.0.join("missing");
        let sidecar = directory.0.join("sidecar");
        symlink(&target, &sidecar).unwrap();
        assert!(matches!(
            open_sidecar(&sidecar),
            Err(LockError::UnsafeAlias(_, _))
        ));
        assert!(matches!(
            canonical_path(&sidecar),
            Err(LockError::UnsafeAlias(_, _))
        ));
    }
}
