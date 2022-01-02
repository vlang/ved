# Ved - small and fast text editor written in V

[![Patreon-badge](https://img.shields.io/badge/Patreon-F96854?style=for-the-badge&logo=patreon&logoColor=white)](https://www.patreon.com/vlang)

[![Workflow-badge](https://github.com/vlang/ved/workflows/CI/badge.svg)](https://github.com/vlang/ved/commits/master)

<img width="640" src="https://user-images.githubusercontent.com/687996/63223411-807a7700-c1bd-11e9-82fc-e2362907024a.png"> 


### Building from source

First you need to [install V](https://github.com/vlang/v#installing-v-from-source). This will take a couple of seconds.

```
git clone https://github.com/vlang/ved
cd ved
v .
./ved
```

Ved should build in under a second.

By default V's built-in font rendering is used, but there's an option to use freetype, which arguably provides better rendering:

```
v -gc boehm -d use_freetype .
```

To use freetype, its files need to be installed:

Ubuntu:
```
sudo apt install libfreetype6-dev libx11-dev libxrandr-dev mesa-common-dev libxi-dev libxcursor-dev
```

Fedora:
```
sudo dnf install freetype-devel libXcursor-devel libXi-devel
```

macOS:
```
brew install freetype
```

Windows:
```
v setup-freetype
```

### Communities:

Discord (primary community): https://discord.gg/n7c74HM. Join the #ved channel.

### This is pre-alpha software.

I've been using Ved as my main editor since June 2017 (it was re-written in V in June 2018).
I've set it up to my liking, I know its limitations and how to bypass them.

For everyone else it's going to be unstable and unconfigurable at this stage.

This will be gradually fixed. The goal is to have a stable and highly customizable editor.

### Main features

- Small size (~ 1 MB binary, builds in <1s)
- Hardware accelerated text rendering
- High performance (scrolling through 300k lines with syntax highlighting without any lag)
- Vim mode
- Easy integration with any compiler/build system
- Go to definition, ctrlp (fuzzy file finder)
- Very fast search in all project files
- Integration with git
- Built-in time management system (based on Pomodoro)
- Global shortcuts (bring to front etc)
- Split view
- Workspaces
- Cross-platform (Windows, macOS, Linux)

### Known issues

- No way to change key bindings, color settings, etc
- Vim-mode only
- No mouse support
- No word wrap (I'm used to 80 character lines)
- ~Only ASCII and Cyrillic letters are supported right now~

Most of these are relatively easy to fix.

### Instructions

Ved works best with workspaces (directories with code).
You can have multiple workspaces and quickly switch between them with `C [` and `C ]`.

To open multiple workspaces, run

`ved path/to/project1 path/to/project2`

Key bindings:

`C` is `⌘` on macOS, `Ctrl` on all other systems.

```
C q    exit the editor (type it twice in a row)
C o    open a file
C s    save
C r    reload current file
C p    open ctrlp (fuzzy search)
/      search in current file
C g    copy current file's path to clipboard
t      go to the previous file
gd     go to definition

C c    git commit -am
C -    git diff
?      git grep (search across all files in current workspace)

C u    build current project (build instructions must be located in "build")
C y    alternative build of the current project (build instructions must be located in "build2")
C 1    switch to Ved from any other application (only on macOS for now)

C d    go to the previous split
C e    go to the next split
C [    go to the previous workspace
C ]    go to the next workspace

C a    start a new task
C t    show the Timer/Pomodoro window


```

Supported vi bindings:
```
j k h l
C-F C-B
L H
w b
dw de cw ce ci
di ci
A I
o O
v
zz
y d p J
.
< >
/ * n
gg G
x r
C-n (autocomplete)
```

Many bindings are missing, and the design is not scalable.
Most of them are hard-coded, so there needs to be extra logic for handling `db`, `cb` etc.
This has to be improved.

<!-- Links -->
[workflow-badge]: https://github.com/vlang/ved/workflows/CI/badge.svg
[patreon-badge]: https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fshieldsio-patreon.vercel.app%2Fapi%3Fusername%3Dvlang%26type%3Dpledges

[workflow-url]: https://github.com/vlang/ved/commits/master
[patreon-url]: https://patreon.com/vlang
