fzf :purple_heart: devicon :heart: vim
===============

Things is a fork of `fzf.vim` that adds in support for devicons via the `devicon-lookup` tool

This fork is compatible side by side with `fzf.vim` however it is NOT required! The commands
that this plugin exports are post-fixed so as to NOT conflict with the originals

Due to the rename that took place after the fork updates from upstream need to be applied manually.
Also not all the changes to upstream are relevant cause much of the scope is reduced.
The current latest git commit from `fzf.vim` that is included here is
`e0d131d95364edf940a70127fcb5748b86e6955e`

Example GIF
-----------

![fzf.devicon.fzf example gif](screenshots/example.gif?raw=true)

Installation
------------

### Dependencies

`fzf.devicon.vim` depends on the [devicon-lookup](https://github.com/coreyja/devicon-lookup) utility version >= 0.10.0
This must be installed separately, and can be installed via `cargo`

```
cargo install devicon-lookup
```

fzf.devicon.vim also depends on the basic Vim plugin of [the main fzf
repository][fzf] which means you need to **install both "fzf" and
"fzf.devicon.vim"**.
[README-VIM][README-VIM].

[fzf-main]: https://github.com/junegunn/fzf
[README-VIM]: https://github.com/junegunn/fzf/blob/master/README-VIM.md

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'coreyja/fzf.devicon.vim'
```

`fzf#install()` makes sure that you have the latest binary, but it's optional,
so you can omit it if you use a plugin manager that doesn't support hooks.

### Dependencies

- [fzf][fzf-main] 0.41.1 or above
- For syntax-highlighted preview, install [bat](https://github.com/sharkdp/bat)
- If [delta](https://github.com/dandavison/delta) is available, `:GFilesWithDevicons?`,
  will use it to format `git diff` output.
- `Ag` requires [The Silver Searcher (ag)][ag]
- `Rg` requires [ripgrep (rg)][rg]

Commands
--------

| Command                       | List                                                                    |
| ---                           | ---                                                                     |
| `:FilesWithDevicons [PATH]`   | Files (runs `$FZF_DEFAULT_COMMAND` if defined)                          |
| `:GFilesWithDevicons [OPTS]`  | Git files (`git ls-files`)                                              |
| `:GFilesWithDevicons?`        | Git files (`git status`)                                                |
| `:AgWithDevicons [PATTERN]`   | [ag][ag] search result (`ALT-A` to select all, `ALT-D` to deselect all) |
| `:RgWithDevicons [PATTERN]`   | [rg][rg] search result (`ALT-A` to select all, `ALT-D` to deselect all) |
| `:RGWithDevicons [PATTERN]`   | [rg][rg] search result; relaunch ripgrep on every keystroke             |
| `:LocateWithDevicons PATTERN` | `locate` command output                                                 |

- Most commands support `CTRL-T` / `CTRL-X` / `CTRL-V` key
  bindings to open in a new tab, a new split, or in a new vertical split
- Bang-versions of the commands (e.g. `Ag!`) will open fzf in fullscreen
- You can set `g:fzf_command_prefix` to give the same prefix to the commands
    - e.g. `let g:fzf_command_prefix = 'Fzf'` and you have `FzfFiles`, etc.

License
-------

MIT

[fzf]:       https://github.com/junegunn/fzf
[fzf.vim]:   https://github.com/junegunn/fzf.vim
[run]:       https://github.com/junegunn/fzf/blob/master/README-VIM.md#fzfrun
[vimrc]:     https://github.com/junegunn/dotfiles/blob/master/vimrc
[ag]:        https://github.com/ggreer/the_silver_searcher
[rg]:        https://github.com/BurntSushi/ripgrep
[us]:        https://github.com/SirVer/ultisnips
