static SESSION_GENERATION: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
use crate::auth::TokenBundle;
use zeroize::Zeroizing;

production_or_tauri! {
const SERVICE: &str = "io.github.xjaus.xjaus";
const ACCOUNT: &str = "xbox-auth-v1";

}
// Secret Service is the only authority. The historical fallback is never read or
// modified during normal operation, but explicit logout removes it.
trait SecretStore {
    fn set(&self, blob: &[u8]) -> Result<(), String>;
    fn get(&self) -> Result<Option<Vec<u8>>, String>;
    fn delete(&self) -> Result<(), String>;
}
production_or_tauri! {
struct KeyringStore;
impl SecretStore for KeyringStore {
    fn set(&self, blob: &[u8]) -> Result<(), String> {
        keyring::Entry::new(SERVICE, ACCOUNT)
            .map_err(|_| "Secret Service unavailable".to_string())?
            .set_secret(blob)
            .map_err(|_| "Cannot persist session in Secret Service".to_string())
    }
    fn get(&self) -> Result<Option<Vec<u8>>, String> {
        let entry = keyring::Entry::new(SERVICE, ACCOUNT)
            .map_err(|_| "Secret Service unavailable".to_string())?;
        match entry.get_secret() {
            Ok(secret) => Ok(Some(secret)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(_) => Err("Cannot read Secret Service".into()),
        }
    }
    fn delete(&self) -> Result<(), String> {
        let entry = keyring::Entry::new(SERVICE, ACCOUNT)
            .map_err(|_| "Secret Service unavailable".to_string())?;
        match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(_) => Err("Could not remove the secret from Secret Service".into()),
        }
    }
}}

#[derive(serde::Serialize, serde::Deserialize)]
struct VersionedBundle<T> {
    bundle_version: u64,
    updated_at_utc: u64,
    #[serde(default)]
    generation: u64,
    bundle: T,
}
fn save_to(store: &dyn SecretStore, bundle: &TokenBundle) -> Result<(), String> {
    let blob = Zeroizing::new(serde_json::to_vec(bundle).map_err(|_| "Cannot encode session")?);
    store.set(&blob)
}
fn load_from(store: &dyn SecretStore) -> Result<Option<TokenBundle>, String> {
    let Some(secret) = store.get()? else {
        return Ok(None);
    };
    let secret = Zeroizing::new(secret);
    if let Ok(versioned) = serde_json::from_slice::<VersionedBundle<TokenBundle>>(&secret) {
        return Ok(Some(versioned.bundle));
    }
    serde_json::from_slice::<TokenBundle>(&secret)
        .map(Some)
        .map_err(|_| "Invalid session in Secret Service".into())
}
#[cfg(target_os = "linux")]
fn auth_state_root() -> Result<std::path::PathBuf, String> {
    let base = match std::env::var_os("XDG_STATE_HOME") {
        Some(path) if std::path::Path::new(&path).is_absolute() => std::path::PathBuf::from(path),
        Some(_) => return Err("XDG_STATE_HOME must be an absolute path".into()),
        None => std::path::PathBuf::from(
            std::env::var_os("HOME").ok_or("HOME is unavailable")?,
        )
        .join(".local/state"),
    };
    Ok(base.join("io.github.xjaus.xjaus/auth-state"))
}
pub fn generation() -> Result<u64, String> {
    #[cfg(all(target_os = "linux", not(test)))]
    {
        return crate::logout_barrier::LogoutBarrier::acquire(&auth_state_root()?)?.generation();
    }
    #[cfg(any(not(target_os = "linux"), test))]
    Ok(SESSION_GENERATION.load(std::sync::atomic::Ordering::SeqCst))
}
#[cfg(test)]
fn begin_login_at(root: &std::path::Path) -> Result<u64, String> {
    let barrier = crate::logout_barrier::LogoutBarrier::acquire(root)?;
    barrier.advance()?;
    barrier.generation()
}
pub fn begin_login() -> Result<u64, String> {
    #[cfg(all(target_os = "linux", not(test)))]
    {
        let barrier = crate::logout_barrier::LogoutBarrier::acquire(&auth_state_root()?)?;
        barrier.advance()?;
        let generation = barrier.generation()?;
        SESSION_GENERATION.store(generation, std::sync::atomic::Ordering::SeqCst);
        return Ok(generation);
    }
    #[cfg(any(not(target_os = "linux"), test))]
    Ok(SESSION_GENERATION
        .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
        .wrapping_add(1))
}
pub fn save_if_generation(
    bundle: &TokenBundle,
    current: &TokenBundle,
    expected: u64,
) -> Result<(), String> {
    #[cfg(all(target_os = "linux", not(test)))]
    {
        return save_if_generation_at(&KeyringStore, &auth_state_root()?, bundle, current, expected);
    }
    #[cfg(all(target_os = "linux", test))]
    if generation()? != expected {
        return Err("Session invalidated by logout or another login".into());
    }
    #[cfg(not(target_os = "linux"))]
    if generation()? != expected {
        return Err("Session invalidated by logout or another login".into());
    }
    Ok(())
}
#[cfg(any(test, target_os = "linux"))]
fn save_if_generation_at(
    store: &dyn SecretStore,
    root: &std::path::Path,
    bundle: &TokenBundle,
    current: &TokenBundle,
    expected: u64,
) -> Result<(), String> {
    let barrier = crate::logout_barrier::LogoutBarrier::acquire(root)?;
    if barrier.blocked()? || barrier.generation()? != expected {
        return Err("Session invalidated by logout or another login".into());
    }
    let stored = load_from(store)?.ok_or("Stored session no longer exists")?;
    if serde_json::to_vec(&stored).map_err(|_| "Cannot compare session")?
        != serde_json::to_vec(current).map_err(|_| "Cannot compare session")?
    {
        return Err("Session changed in another process".into());
    }
    save_versioned_to(store, bundle, expected)
}
production_or_tauri! {
    pub fn save(bundle: &TokenBundle) -> Result<(), String> {
        #[cfg(all(target_os = "linux", not(test)))]
        {
            let barrier = crate::logout_barrier::LogoutBarrier::acquire(&auth_state_root()?)?;
            if barrier.blocked()? {
                return Err("No authorized login generation".into());
            }
            return save_versioned_to(&KeyringStore, bundle, barrier.generation()?);
        }
        #[cfg(any(not(target_os = "linux"), test))]
        Ok(())
    }
}
pub fn login(bundle: &TokenBundle, expected: u64) -> Result<(), String> {
    #[cfg(all(target_os = "linux", not(test)))]
    {
        let barrier = crate::logout_barrier::LogoutBarrier::acquire(&auth_state_root()?)?;
        if barrier.generation()? != expected {
            return Err("Login invalidated by logout".into());
        }
        barrier.block()?;
        save_versioned_to(&KeyringStore, bundle, expected)?;
        barrier.unblock()?;
        return Ok(());
    }
    #[cfg(any(not(target_os = "linux"), test))]
    if generation()? != expected {
        return Err("Login invalidated by logout".into());
    }
    Ok(())
}
#[cfg(test)]
fn login_at(
    store: &dyn SecretStore,
    root: &std::path::Path,
    bundle: &TokenBundle,
    expected: u64,
) -> Result<(), String> {
    let barrier = crate::logout_barrier::LogoutBarrier::acquire(root)?;
    if barrier.generation()? != expected {
        return Err("Login invalidated by logout".into());
    }
    // Keep the barrier in place if any write or sync fails.
    barrier.block()?;
    save_versioned_to(store, bundle, expected)?;
    barrier.unblock()
}
#[cfg(any(test, target_os = "linux"))]
fn load_guarded(
    store: &dyn SecretStore,
    root: &std::path::Path,
) -> Result<Option<TokenBundle>, String> {
    let barrier = crate::logout_barrier::LogoutBarrier::acquire(root)?;
    if barrier.blocked()? {
        return Ok(None);
    }
    let expected = barrier.generation()?;
    let Some(secret) = store.get()? else { return Ok(None) };
    let secret = Zeroizing::new(secret);
    let Ok(stored) = serde_json::from_slice::<VersionedBundle<TokenBundle>>(&secret) else {
        return Ok(None);
    };
    if stored.bundle_version != 1 || stored.generation != expected {
        return Ok(None);
    }
    Ok(Some(stored.bundle))
}
production_or_tauri! {
    pub fn load() -> Result<Option<TokenBundle>, String> {
        #[cfg(all(target_os = "linux", not(test)))]
        {
            return load_guarded(&KeyringStore, &auth_state_root()?);
        }
        #[cfg(any(not(target_os = "linux"), test))]
        Ok(None)
    }
}
fn delete_from(
    store: &dyn SecretStore,
    path: Result<Option<std::path::PathBuf>, String>,
) -> Result<(), String> {
    let secret_result = store.delete();
    let legacy_result = path.and_then(|path| match path {
        None => Ok(()),
        Some(path) => match std::fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(format!("Cannot remove legacy auth.enc: {error}")),
        },
    });
    match (secret_result, legacy_result) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error),
        (Err(secret), Err(legacy)) => Err(format!("{secret}; {legacy}")),
    }
}
// The old implementation used HOME on every platform, never USERPROFILE.
fn legacy_path(
    home: Option<std::ffi::OsString>,
    windows: bool,
) -> Result<Option<std::path::PathBuf>, String> {
    match home {
        Some(home) => Ok(Some(
            std::path::PathBuf::from(home).join(".local/share/io.github.xjaus.xjaus/auth.enc"),
        )),
        None if windows => Ok(None),
        None => Err("HOME is unavailable; cannot remove legacy auth.enc".to_string()),
    }
}
#[cfg(test)]
fn delete_guarded(
    store: &dyn SecretStore,
    path: Result<Option<std::path::PathBuf>, String>,
    root: &std::path::Path,
) -> Result<(), String> {
    let barrier = crate::logout_barrier::LogoutBarrier::acquire(root);
    let barrier_result = match &barrier {
        Ok(barrier) => {
            let blocked = barrier.block();
            let advanced = barrier.advance();
            blocked.and(advanced)
        }
        Err(e) => Err(e.clone()),
    };
    let deletion_result = delete_from(store, path);
    barrier_result.and(deletion_result)
}
pub fn invalidate_memory_generation() {
    SESSION_GENERATION.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
}

tauri_only! {
    pub fn delete() -> Result<(), String> {
        invalidate_memory_generation();
        delete_persistent()
    }
}

production_or_tauri! {
    pub fn delete_persistent() -> Result<(), String> {
        #[cfg(all(target_os = "linux", not(test)))]
        {
            let barrier = crate::logout_barrier::LogoutBarrier::acquire(&auth_state_root()?)?;
            barrier.block()?;
            barrier.advance()?;
            return delete_from(&KeyringStore, legacy_path(std::env::var_os("HOME"), false));
        }
        #[cfg(any(not(target_os = "linux"), test))]
        delete_from(&KeyringStore, legacy_path(std::env::var_os("HOME"), false))
    }
}

fn save_versioned_to(
    store: &dyn SecretStore,
    bundle: &TokenBundle,
    generation: u64,
) -> Result<(), String> {
    let blob = Zeroizing::new(
        serde_json::to_vec(&VersionedBundle {
            bundle_version: 1,
            updated_at_utc: now_unix(),
            generation,
            bundle,
        })
        .map_err(|_| "Cannot encode session")?,
    );
    store.set(&blob)
}

fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    #[test]
    fn unblocked_marker_must_not_restore_old_session() {
        let root =
            std::env::temp_dir().join(format!("xjaus-old-session-red-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let store = Store::default();
        save_to(&store, &bundle("synthetic-old-session")).unwrap();
        let barrier = crate::logout_barrier::LogoutBarrier::acquire(&root).unwrap();
        barrier.advance().unwrap();
        barrier.unblock().unwrap();
        drop(barrier);
        assert!(
            load_guarded(&store, &root).unwrap().is_none(),
            "an unblocked marker must not authorize restoration"
        );
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn missing_durable_state_never_restores_existing_secret() {
        let root = std::env::temp_dir().join(format!("xjaus-missing-state-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let store = Store::default();
        save_to(&store, &bundle("old")).unwrap();
        assert!(matches!(load_guarded(&store, &root), Ok(None) | Err(_)));
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn stale_login_and_refresh_cannot_replace_new_session() {
        let root = std::env::temp_dir().join(format!("xjaus-stale-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let store = Store::default();
        let old = bundle("old");
        save_to(&store, &old).unwrap();
        let first = begin_login_at(&root).unwrap();
        let second = begin_login_at(&root).unwrap();
        let new = bundle("new");
        login_at(&store, &root, &new, second).unwrap();
        assert!(login_at(&store, &root, &old, first).is_err());
        assert!(save_if_generation_at(&store, &root, &old, &old, first).is_err());
        assert_eq!(
            serde_json::to_value(load_from(&store).unwrap().unwrap()).unwrap(),
            serde_json::to_value(new).unwrap()
        );
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn new_login_invalidates_older_attempt_before_completion() {
        let root =
            std::env::temp_dir().join(format!("xjaus-login-generation-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let first = begin_login_at(&root).unwrap();
        let second = begin_login_at(&root).unwrap();
        assert_ne!(first, second);
        assert_ne!(
            crate::logout_barrier::LogoutBarrier::acquire(&root)
                .unwrap()
                .generation()
                .unwrap(),
            first
        );
        std::fs::remove_dir_all(root).unwrap();
    }
    #[derive(Default)]
    struct Store {
        value: Mutex<Option<Vec<u8>>>,
        unavailable: bool,
    }
    impl SecretStore for Store {
        fn set(&self, blob: &[u8]) -> Result<(), String> {
            if self.unavailable {
                return Err("unavailable".into());
            }
            *self.value.lock().unwrap() = Some(blob.to_vec());
            Ok(())
        }
        fn get(&self) -> Result<Option<Vec<u8>>, String> {
            if self.unavailable {
                return Err("unavailable".into());
            }
            Ok(self.value.lock().unwrap().clone())
        }
        fn delete(&self) -> Result<(), String> {
            if self.unavailable {
                return Err("unavailable".into());
            }
            *self.value.lock().unwrap() = None;
            Ok(())
        }
    }
    fn bundle(name: &str) -> TokenBundle {
        serde_json::from_value(serde_json::json!({"refresh_token":name,"acquired_at_unix":1}))
            .unwrap()
    }
    #[test]
    fn authoritative_store_ignores_newer_legacy_file_and_preserves_it() {
        let store = Store::default();
        let mut nonce = [0u8; 16];
        getrandom::getrandom(&mut nonce).unwrap();
        let dir = std::env::temp_dir().join(format!("xjaus-vault-test-{}", hex::encode(nonce)));
        std::fs::create_dir(&dir).unwrap();
        let path = dir.join("auth.enc");
        std::fs::write(&path, b"synthetic legacy blob").unwrap();
        let current = bundle("keyring-fixture");
        save_to(&store, &current).unwrap();
        assert_eq!(
            serde_json::to_value(load_from(&store).unwrap().unwrap()).unwrap(),
            serde_json::to_value(current).unwrap()
        );
        assert_eq!(std::fs::read(&path).unwrap(), b"synthetic legacy blob");
        delete_from(&store, Ok(Some(path.clone()))).unwrap();
        assert!(load_from(&store).unwrap().is_none());
        assert!(
            !path.exists(),
            "explicit logout must remove the legacy file"
        );
        std::fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn logout_attempts_both_deletions_and_reports_failures() {
        let mut nonce = [0u8; 16];
        getrandom::getrandom(&mut nonce).unwrap();
        let dir = std::env::temp_dir().join(format!("xjaus-vault-errors-{}", hex::encode(nonce)));
        std::fs::create_dir(&dir).unwrap();
        let path = dir.join("auth.enc");
        std::fs::write(&path, b"fixture").unwrap();
        let unavailable = Store {
            unavailable: true,
            ..Default::default()
        };
        assert_eq!(
            delete_from(&unavailable, Ok(Some(path.clone()))).unwrap_err(),
            "unavailable"
        );
        assert!(!path.exists());
        assert!(delete_from(&Store::default(), Ok(Some(path))).is_ok());
        let store = Store::default();
        store.set(b"fixture").unwrap();
        let error = delete_from(&store, Ok(Some(dir.clone()))).unwrap_err();
        assert!(error.contains("Cannot remove legacy auth.enc"));
        assert!(store.get().unwrap().is_none());
        let error = delete_from(&unavailable, Ok(Some(dir.clone()))).unwrap_err();
        assert!(error.contains("unavailable") && error.contains("Cannot remove legacy auth.enc"));
        std::fs::remove_dir(dir).unwrap();
    }
    #[test]
    fn legacy_path_respects_historical_home_and_platform() {
        use std::ffi::OsString;
        let home = OsString::from("synthetic-home");
        for windows in [false, true] {
            assert_eq!(
                legacy_path(Some(home.clone()), windows).unwrap(),
                Some(
                    std::path::PathBuf::from(&home)
                        .join(".local/share/io.github.xjaus.xjaus/auth.enc")
                )
            );
        }
        assert_eq!(legacy_path(None, true).unwrap(), None);
        let store = Store::default();
        store.set(b"synthetic").unwrap();
        assert!(delete_from(&store, legacy_path(None, true)).is_ok());
        assert!(store.get().unwrap().is_none());
        assert!(
            legacy_path(None, false)
                .unwrap_err()
                .contains("HOME is unavailable")
        );
    }
    #[test]
    fn failed_logout_must_prevent_restart_from_loading_old_secret() {
        struct DeleteFailure(Store);
        impl SecretStore for DeleteFailure {
            fn set(&self, blob: &[u8]) -> Result<(), String> {
                self.0.set(blob)
            }
            fn get(&self) -> Result<Option<Vec<u8>>, String> {
                self.0.get()
            }
            fn delete(&self) -> Result<(), String> {
                Err("synthetic delete failure".into())
            }
        }
        let store = DeleteFailure(Store::default());
        save_to(&store, &bundle("synthetic-old-session")).unwrap();
        // Simulate a keyring deletion failure while durable state remains writable.
        let root = std::env::temp_dir().join(format!("xjaus-red-green-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let result = delete_guarded(&store, Ok(None), &root);
        assert!(result.is_err());
        assert!(load_guarded(&store, &root).unwrap().is_none());
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn unavailable_store_fails_closed_for_all_operations() {
        let store = Store {
            unavailable: true,
            ..Default::default()
        };
        assert!(save_to(&store, &bundle("fixture")).is_err());
        assert!(load_from(&store).is_err());
        assert!(store.delete().is_err());
    }
    #[test]
    fn versioned_and_plain_keyring_entries_remain_readable() {
        let store = Store::default();
        let current = bundle("fixture");
        let wrapped = VersionedBundle {
            bundle_version: 3,
            updated_at_utc: 2,
            generation: 0,
            bundle: current.clone(),
        };
        store.set(&serde_json::to_vec(&wrapped).unwrap()).unwrap();
        assert_eq!(
            serde_json::to_value(load_from(&store).unwrap().unwrap()).unwrap(),
            serde_json::to_value(&current).unwrap()
        );
        save_to(&store, &current).unwrap();
        assert!(load_from(&store).unwrap().is_some());
        store.set(b"not a session").unwrap();
        assert!(load_from(&store).is_err());
    }
}

tauri_only! {
    #[cfg(test)]
    #[path = "vault/logout_security.rs"]
    mod logout_security;
}
