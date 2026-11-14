# Contributing

These hold for everyone working on this project, people and AI assistants alike. This project's own
rules follow at the end.

## Report a bug or ask for something

Open an issue with the bug, request or task form.

## Track work

- An open task is an issue in the repo it belongs to. Nothing else is a task list: no notes file,
  no assistant memory or queue, no session.
- Before opening an issue, search the open ones. What an existing issue covers is added to it: one
  matter is one issue.
- An assistant opens an issue in two cases only: the person it works for asked for something that
  is not finished when work ends, or it verified a defect.
- An idea, a maybe or a question is said once and dropped. It becomes an issue, with `later`, only
  when that person says keep it.
- An issue has one type, which its form sets. Add `later` to an idea nobody owes and `waiting` to
  one blocked on a person, a delivery or a decision. An issue that is not ours to solve, or no
  longer true, is closed with one sentence saying why.
- An issue's goal stays in the words it was opened with. Later work ticks its "Done when" list and
  comments; it does not rewrite the goal.
- Never record state, such as what was exported, what runs where or what was done: that is read at
  its source. Record only what someone must still act on. A one-off, such as a file exported for a
  meeting, is not recorded.
- Before starting work, read the repo's open issues. When work ends, close what is done, and open
  an issue for what was asked and is not finished.

## Make a change

- Read the code the change touches first.
- Run `nix flake check` before you commit. A red `main` is fixed before anything else.
- The commit message says why the change was made. A decision that shapes the project also gets
  one short file in `docs/`.
- A fix names the cause it removes. When a later fix names another cause for the same failure, the
  earlier fix comes out in that change unless it is proven on its own. Unmeasured is not proven.
- A doc says only what the code cannot: a decision, a fact about an outside system, or a trap no
  check catches. It never repeats what the code, a check's message or a command's usage says, and
  never copies state such as counts, versions or what runs where: that is read at its source. A
  wrong line is deleted or fixed when seen.
- An open point is written as the question that is open, never as an errand: no line about a person
  asking, waiting on or confirming something with someone else.
- Nothing that exists only on your own machine goes into the project, or into an issue, a pull
  request or a comment on one: no personal names, addresses, machines, hardware, paths, tools or
  habits.
- Never hide an error. Read a result from the check's own exit code.

## Improve these rules

These rules grow with the work. A rule for this project goes under This project below. A rule for
every repo goes to `Daaboulex/nix-packaging-standard` as an issue or a change, and reaches each
repo with the next release.

## This project
