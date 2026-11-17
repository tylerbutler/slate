# Unicode filename migration

Ordinary table opens and `slate.is_dets_file` now decode Gleam paths as UTF-8.
They select the filename as written, as exclusive sessions already do.
Previously, ordinary opens interpreted each UTF-8 byte as a separate character.
For example, the path `café.dets` could create `cafÃ©.dets` on disk.
ASCII filenames and the DETS file format do not change.

There is **no automatic fallback** to the old filename. An existing correctly
named Unicode file is opened directly. If only the old name exists, `ReadOnly`
cannot open it, and `ReadWrite` creates a new, empty table at the requested name.
This does not move or delete the old file. The two names can hold different data.

## Move an affected file safely

1. Stop all access to both filenames. Close every table and stop all applications,
   CLI commands, and BEAM VMs that can reopen either file. Include older clients
   and exclusive-session clients.
2. Back up both files, if present, with their exact names and directory paths.
   Keep the backups separate from the working directory. Do not repair, rename,
   or delete files before the backups are complete.
3. Inspect the directory and both names. Do not infer the old name from how a
   terminal displays it. Use filesystem tools that show the exact filename bytes
   or Unicode code points. Inspect copies with read-only DETS operations to
   identify which dataset each file contains.
4. If the requested name is absent, move the identified old file to that name
   with a tool that refuses to replace an existing destination. Check that the
   destination is still absent immediately before the move.
5. If both names exist, **do not overwrite either file**. They can contain
   independent writes. Keep both backups and decide which dataset to use, or
   reconcile their records in a separate file before switching the application.
6. With all other clients still stopped, open the selected file with the updated
   library in `ReadOnly` mode and check known records. Close it before restarting
   the application.

Do not delete or replace `.slate.lock` sidecars while any client can access the
files. After migration, use the same filename and compatible library version in
every client. To roll back, first stop all access again; do not start an old
client against a changed directory and assume it will select the same dataset.
