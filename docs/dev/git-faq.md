# Git FAQ

## Why doesn't `git diff` show my new (untracked) files?

`git diff` only compares files that are already tracked in the repository. Completely new files live in the "untracked" state, so it has no previous version to diff against and silently skips them.

### How to include new files in a diff

1. **Stage the file first**
   - `git add path/to/new_file`
   - `git diff --cached path/to/new_file`
   - Staging tells Git to treat the file as tracked, so the diff shows the added content.

2. **Use a `/dev/null` comparison (no staging required)**
   - `git diff --no-index -- /dev/null path/to/new_file`
   - This explicitly compares an empty file to your new file and works even if the file remains untracked.

3. **Export a patch directly**
   - `git diff --no-index -- /dev/null path/to/new_file > my_new_file.patch`
   - Useful when you need a standalone patch file without touching the index.

### Related tips

- `git status` lists all untracked files so you can confirm what still needs staging.
- `git diff --stat` also ignores untracked files; combine it with the techniques above if you need the new file to appear in summary output.
