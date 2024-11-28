<h1 align="center">Ved</h1>
<h3 align="center">A small and fast text editor written in V</h3>

<img src="https://user-images.githubusercontent.com/47652746/199333211-ee78f600-039c-4d96-85ec-e5580fca6736.jpg" alt="Screenshot of the editor">

[![Patreon-badge](https://img.shields.io/badge/Patreon-F96854?logo=patreon&logoColor=white)](https://www.patreon.com/vlang)
![GitHub Workflow Status (event)](https://img.shields.io/github/actions/workflow/status/vlang/ved/ci.yml?branch=master)

### This is pre-alpha software.

I've been using Ved as my main editor since June 2017 (it was re-written in V in June 2018).

It may not work for everyone. There are currently limitations that must be worked around.
We are working on slowly improving the ved stability and user experience.

To configure the editor, please see the [configuration](#configuration) section.

### Building from source

On Linux, you need to [install some packages](https://github.com/vlang/v?tab=readme-ov-file#testing-and-running-the-examples),
need to use X11 libraries, since Ved is a graphical application.
Then [install V](https://github.com/vlang/v#installing-v---from-source-preferred-method) and compile ved.
This will take a couple of seconds.

```
git clone https://github.com/vlang/ved
cd ved
v .
./ved
```

Ved should build in under a second.

By default V's built-in font rendering is used, but there's an option to use freetype,
which may provide better rendering for some users:

```
v -d use_freetype .
```

To use freetype, it must first be installed on your system.
Follow the steps for your platform below.

Ubuntu:
```
sudo apt install libfreetype6-dev libx11-dev libxrandr-dev mesa-common-dev libxi-dev libxcursor-dev
```

Fedora:
```
sudo dnf install freetype-devel libXcursor-devel libXi-devel
```

Arch:
```
pacman -S freetype2
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

Discord (primary community): https://discord.gg/vlang. Join the `#ved` channel.

### Main features

- Small size (~ 1 MB binary, builds in <1s)
- Hardware accelerated text rendering
- High performance (scrolling through 300k lines with syntax highlighting without any lag)
- WIP Vim mode
- Easy integration with any compiler/build system
- Go to definition
- Fuzzy file finder
- Fast search
- Integration with git
- Built-in time management system (based on Pomodoro)
- Global bring-to-front key
- Split view
- Workspaces
- Cross-platform (Windows, macOS, GNU/Linux)

### Planned features

- True vim mode (current implementation only implements a small subset of vim's features)
- Emacs keybindings
- Nano keybindings
- Word wrap
- Better syntax highlighting

### Configuration

Ved creates a settings directory in `$HOME/.ved` where it stores workspaces,
sessions, tasks, and the configuration file.
The configuration file is simply a [TOML](https://toml.io/) file called `conf.toml`.
It provides a way to change some basic settings and the editor colors.

If you don't want to touch the config file, you never have to!
Ved does not create it by itself and it provides sensible defaults to get you started.
If you are more adventurous, here is an example configuration file that contains all
of the possible settings:

```toml
# To get started, create a file called "conf.toml" in $HOME/.ved
# Most of the settings are contained inside this "editor" table.
[editor]
dark_mode = false       # Ved comes with a light and dark mode built-in.
cursor = 'variable'     # Ved has three variants: Variable, block, and beam. You are probably used to "variable" or "beam".
text_size = 18          # ┌───────────────────────────────────────────────────┐
line_height = 20        # │ These *can* be edited, but you probably shouldn't │
char_width = 8          # └───────────────────────────────────────────────────┘
tab_size = 4            # Ved uses tab characters (\t). This settings changes how many spaces a tab should be displayed as
backspace_go_up = true  # If set to true, hitting the backspace doesn't do anything when you reach the beginning of the line

# If you do not like ved's default colorscheme, or you just want
# something new, edit the "colors" table. Ved uses a form of base16
# to control syntax and editor highlighting. Please note that due
# to ved's very minimal highlighting, base16 themes copied off of
# the internet are not going to look like very much like their
# screenshots.
[colors]
base00 = "efecf4"
base01 = "e2dfe7"
base02 = "8b8792"
base03 = "7e7887"
base04 = "655f6d"
base05 = "585260"
base06 = "26232a"
base07 = "19171c"
base08 = "be4678"
base09 = "aa573c"
base0A = "a06e3b"
base0B = "2a9292"
base0C = "398bc6"
base0D = "576ddb"
base0E = "955ae7"
base0F = "bf40bf"
```

### Basic usage

Ved works best with workspaces (directories with code).
You can have multiple workspaces and quickly switch between them with `C [` and `C ]`.

To open multiple workspaces, run

`ved path/to/project1 path/to/project2`

Key bindings:

`C` is `⌘` on macOS, `Ctrl` on all other systems.

```
C q q  exit the editor
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

Supported vim bindings:
```
j k h l         down, up, left, right (moves cursor)
C-F C-B         page down, page up
L H             go to top/bottom of the page
w b             next/previous word
dw de cw ce     delete word
di ci           smart delete
A I             go to start/end of line, insert mode
o O             new line below/above, insert mode
v               selection mode
zz              center current line
y d p J         yank, delete, paste, join lines
.               repeat last action
< >             indent right/left
/ * n           search, search for word under cursor, next occurence
gg G            go to the beginning/end of the file
x r             delete/replace character under cursor
C-n             autocomplete
+y              yank and copy to system clipboard
```

