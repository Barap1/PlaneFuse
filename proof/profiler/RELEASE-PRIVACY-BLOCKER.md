# Profiler publication privacy blocker

The current tree contains only sanitized profiler exports. Earlier committed
Metal TOC/export files contained a device nickname, hardware UUID, PIDs, and
unrelated process/application inventory; those files were removed from the
current tree without rewriting Git history. Existing private repository history
must remain unchanged unless the human explicitly authorizes history
sanitization/rewrite.

Before repository publication, choose one of:

1. explicitly approve history sanitization/rewrite; or
2. publish from a clean sanitized repository/history containing the final source
   and evidence tree.

The privacy checker is `python3 -B scripts/check_r7_profiler_privacy.py`.
