# Test harnesses

## Shell scripts

Run a shipped `fort/scripts/*.sh` file with `bash` from a `git init`'d
temporary directory. `emit.sh` resolves `git-common-dir` from that temporary
fort, so its event write is isolated under the temporary directory while the
test exercises the actual shipped script. Clean the directory in `afterEach`.

Use a fixed `-T` timestamp for assertions against an event file and its JSON.
For a newly covered script, keep the test in `test/shell.test.ts` unless its
setup needs a separate fixture.
