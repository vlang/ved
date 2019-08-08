# Vid - small and fast text editor written in V

### Building from source

First you need to [install V](https://github.com/vlang/v#installing-v-from-source). This will take a couple of seconds.

```
git clone https://github.com/vlang/vid
cd vid
v .
./vid
```

### This is pre-alpha software.

I've been using Vid as my main editor since June 2017 (it was re-writtein in V in June 2018). I've set it up to my liking, I know its limitations and how to bypass them. 

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
- Only ASCII and Cyrillic letters are supported right now

Most of these are relatively easy to fix.

### Instructions

Vid works best with workspaces (directories with code). You can have multiple workspaces and quickly switch between them with `C [` and `C ]`.

To open multiple workspaces, run

`vid path/to/project1 path/to/project2 `

Key bindings:

`C` is `⌘` on macOS, `Ctrl` on all other systems.

```
C o    open a file
C s    save
C r    reload current file
C p    open ctrlp (fuzzy search)
/      search in current file
C g    copy current file's path to clipboard
tt     go to the previous file

C c    git commit -am
C -    git diff
?      git grep (search across all files in current workspace)

C u    build current project (build instructions must be located in "build")
C y    alternative build of the current project (build instructions must be located in "build2")
C 1    switch to Vid from any other application (only on macOS for now)

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
dw de cw ce
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
```



Many bindings are missing, and the design is not scalable. Most of them are hard-coded, so there needs to be extra logic for handling `db`, `cb` etc. This has to be improved.








![](https://user-images.githubusercontent.com/687996/53506877-2377f100-3ab7-11e9-8984-d185d632bcb7.png)

You can also [have a look at an old demo](https://volt-app.com/img/lang.webm).


