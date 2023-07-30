" Copyright (c) 2017 Junegunn Choi
"
" MIT License
"
" Permission is hereby granted, free of charge, to any person obtaining
" a copy of this software and associated documentation files (the
" "Software"), to deal in the Software without restriction, including
" without limitation the rights to use, copy, modify, merge, publish,
" distribute, sublicense, and/or sell copies of the Software, and to
" permit persons to whom the Software is furnished to do so, subject to
" the following conditions:
"
" The above copyright notice and this permission notice shall be
" included in all copies or substantial portions of the Software.
"
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
" EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
" MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
" NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
" LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
" OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
" WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

let s:cpo_save = &cpoptions
set cpoptions&vim

" ------------------------------------------------------------------
" Common
" ------------------------------------------------------------------

let s:winpath = {}
function! s:winpath(path)
  if has_key(s:winpath, a:path)
    return s:winpath[a:path]
  endif

  let winpath = split(system('for %A in ("'.a:path.'") do @echo %~sA'), "\n")[0]
  let s:winpath[a:path] = winpath

  return winpath
endfunction

let s:warned = 0
function! s:bash()
  if exists('s:bash')
    return s:bash
  endif

  let custom_bash = get(g:, 'fzf_preview_bash', '')
  let git_bash = 'C:\Program Files\Git\bin\bash.exe'
  let candidates = filter(s:is_win ? [custom_bash, 'bash', git_bash] : [custom_bash, 'bash'], 'len(v:val)')

  let found = filter(map(copy(candidates), 'exepath(v:val)'), 'len(v:val)')
  if empty(found)
    if !s:warned
      call s:warn(printf('Preview window not supported (%s not found)', join(candidates, ', ')))
      let s:warned = 1
    endif
    let s:bash = ''
    return s:bash
  endif

  let s:bash = found[0]

  " Make 8.3 filename via cmd.exe
  if s:is_win
    let s:bash = s:winpath(s:bash)
  endif

  return s:bash
endfunction

function! s:escape_for_bash(path)
  if !s:is_win
    return fzf#shellescape(a:path)
  endif

  if !exists('s:is_linux_like_bash')
    call system(s:bash . ' -c "ls /mnt/[A-Za-z]"')
    let s:is_linux_like_bash = v:shell_error == 0
  endif

  let path = substitute(a:path, '\', '/', 'g')
  if s:is_linux_like_bash
    let path = substitute(path, '^\([A-Z]\):', '/mnt/\L\1', '')
  endif

  return escape(path, ' ')
endfunction

let s:min_version = '0.23.0'
let s:is_win = has('win32') || has('win64')
let s:is_wsl_bash = s:is_win && (exepath('bash') =~? 'Windows[/\\]system32[/\\]bash.exe$')
let s:layout_keys = ['window', 'up', 'down', 'left', 'right']
let s:bin_dir = expand('<sfile>:p:h:h:h:h').'/bin/'
let s:bin = {
\ 'preview': s:bin_dir.'preview.sh'}
let s:TYPE = {'bool': type(0), 'dict': type({}), 'funcref': type(function('call')), 'string': type(''), 'list': type([])}
if s:is_win
  if has('nvim')
    let s:bin.preview = split(system('for %A in ("'.s:bin.preview.'") do @echo %~sA'), "\n")[0]
  else
    let s:bin.preview = fnamemodify(s:bin.preview, ':8')
  endif
  let s:bin.preview = 'bash '.escape(s:bin.preview, '\')

  function! s:fzf_call(fn, ...)
    let shellslash = &shellslash
    try
      set noshellslash
      return call(a:fn, a:000)
    finally
      let &shellslash = shellslash
    endtry
  endfunction
else
  function! s:fzf_call(fn, ...)
    return call(a:fn, a:000)
  endfunction
endif

let s:wide = 120
let s:checked = 0

function! s:check_requirements()
  if s:checked
    return
  endif

  if !exists('*fzf#run')
    throw "fzf#run function not found. You also need Vim plugin from the main fzf repository (i.e. junegunn/fzf *and* junegunn/fzf.vim)"
  endif
  if !exists('*fzf#exec')
    throw "fzf#exec function not found. You need to upgrade Vim plugin from the main fzf repository ('junegunn/fzf')"
  endif
  let s:checked = !empty(fzf#exec(s:min_version))
endfunction

function! s:extend_opts(dict, eopts, prepend)
  if empty(a:eopts)
    return
  endif
  if has_key(a:dict, 'options')
    if type(a:dict.options) == s:TYPE.list && type(a:eopts) == s:TYPE.list
      if a:prepend
        let a:dict.options = extend(copy(a:eopts), a:dict.options)
      else
        call extend(a:dict.options, a:eopts)
      endif
    else
      let all_opts = a:prepend ? [a:eopts, a:dict.options] : [a:dict.options, a:eopts]
      let a:dict.options = join(map(all_opts, 'type(v:val) == s:TYPE.list ? join(map(copy(v:val), "fzf#shellescape(v:val)")) : v:val'))
    endif
  else
    let a:dict.options = a:eopts
  endif
endfunction

function! s:merge_opts(dict, eopts)
  return s:extend_opts(a:dict, a:eopts, 0)
endfunction

function! s:prepend_opts(dict, eopts)
  return s:extend_opts(a:dict, a:eopts, 1)
endfunction

" [spec to wrap], [preview window expression], [toggle-preview keys...]
function! fzf#devicon#vim#with_preview(...)
  " Default spec
  let spec = {}
  let window = ''

  let args = copy(a:000)

  " Spec to wrap
  if len(args) && type(args[0]) == s:TYPE.dict
    let spec = copy(args[0])
    call remove(args, 0)
  endif

  if !executable(s:bash())
    return spec
  endif

  " Placeholder expression (TODO/TBD: undocumented)
  let placeholder = get(spec, 'placeholder', '{}')

  " g:fzf_preview_window
  if empty(args)
    let preview_args = get(g:, 'fzf_preview_window', ['', 'ctrl-/'])
    if empty(preview_args)
      let args = ['hidden']
    else
      " For backward-compatiblity
      let args = type(preview_args) == type('') ? [preview_args] : copy(preview_args)
    endif
  endif

  if len(args) && type(args[0]) == s:TYPE.string
    if len(args[0]) && args[0] !~# '^\(up\|down\|left\|right\|hidden\)'
      throw 'invalid preview window: '.args[0]
    endif
    let window = args[0]
    call remove(args, 0)
  endif

  let preview = []
  if len(window)
    let preview += ['--preview-window', window]
  endif
  if s:is_win
    if empty($MSWINHOME)
      let $MSWINHOME = $HOME
    endif
    if s:is_wsl_bash && $WSLENV !~# '[:]\?MSWINHOME\(\/[^:]*\)\?\(:\|$\)'
      let $WSLENV = 'MSWINHOME/u:'.$WSLENV
    endif
  endif
  let preview_cmd = s:bash() . ' ' . s:escape_for_bash(s:bin.preview)
  if len(placeholder)
    let preview += ['--preview', preview_cmd.' '.placeholder]
  end
  if &ambiwidth ==# 'double'
    let preview += ['--no-unicode']
  end

  if len(args)
    call extend(preview, ['--bind', join(map(args, 'v:val.":toggle-preview"'), ',')])
  endif
  call s:merge_opts(spec, preview)
  return spec
endfunction

function! s:remove_layout(opts)
  for key in s:layout_keys
    if has_key(a:opts, key)
      call remove(a:opts, key)
    endif
  endfor
  return a:opts
endfunction

function! s:reverse_list(opts)
  let tokens = map(split($FZF_DEFAULT_OPTS, '[^a-z-]'), 'substitute(v:val, "^--", "", "")')
  if index(tokens, 'reverse') < 0
    return extend(['--layout=reverse-list'], a:opts)
  endif
  return a:opts
endfunction

function! s:wrap(name, opts, bang)
  " fzf#wrap does not append --expect if sink or sink* is found
  let opts = copy(a:opts)
  let options = ''
  if has_key(opts, 'options')
    let options = type(opts.options) == s:TYPE.list ? join(opts.options) : opts.options
  endif
  if options !~? '--expect' && has_key(opts, 'sink*')
    let Sink = remove(opts, 'sink*')
    let wrapped = fzf#wrap(a:name, opts, a:bang)
    let wrapped['sink*'] = Sink
  else
    let wrapped = fzf#wrap(a:name, opts, a:bang)
  endif
  return wrapped
endfunction

function! s:strip(str)
  return substitute(a:str, '^\s*\|\s*$', '', 'g')
endfunction

function! s:chomp(str)
  return substitute(a:str, '\n*$', '', 'g')
endfunction

function! s:escape(path)
  let path = fnameescape(a:path)
  return s:is_win ? escape(path, '$') : path
endfunction

if v:version >= 704
  function! s:function(name)
    return function(a:name)
  endfunction
else
  function! s:function(name)
    " By Ingo Karkat
    return function(substitute(a:name, '^s:', matchstr(expand('<sfile>'), '<SNR>\d\+_\zefunction$'), ''))
  endfunction
endif

function! s:get_color(attr, ...)
  let gui = has('termguicolors') && &termguicolors
  let fam = gui ? 'gui' : 'cterm'
  let pat = gui ? '^#[a-f0-9]\+' : '^[0-9]\+$'
  for group in a:000
    let code = synIDattr(synIDtrans(hlID(group)), a:attr, fam)
    if code =~? pat
      return code
    endif
  endfor
  return ''
endfunction

let s:ansi = {'black': 30, 'red': 31, 'green': 32, 'yellow': 33, 'blue': 34, 'magenta': 35, 'cyan': 36}

function! s:csi(color, fg)
  let prefix = a:fg ? '38;' : '48;'
  if a:color[0] ==# '#'
    return prefix.'2;'.join(map([a:color[1:2], a:color[3:4], a:color[5:6]], 'str2nr(v:val, 16)'), ';')
  endif
  return prefix.'5;'.a:color
endfunction

function! s:ansi(str, group, default, ...)
  let fg = s:get_color('fg', a:group)
  let bg = s:get_color('bg', a:group)
  let color = (empty(fg) ? s:ansi[a:default] : s:csi(fg, 1)) .
        \ (empty(bg) ? '' : ';'.s:csi(bg, 0))
  return printf("\x1b[%s%sm%s\x1b[m", color, a:0 ? ';1' : '', a:str)
endfunction

for s:color_name in keys(s:ansi)
  execute 'function! s:'.s:color_name."(str, ...)\n"
        \ "  return s:ansi(a:str, get(a:, 1, ''), '".s:color_name."')\n"
        \ 'endfunction'
endfor

function! s:buflisted()
  return filter(range(1, bufnr('$')), 'buflisted(v:val) && getbufvar(v:val, "&filetype") !=? "qf"')
endfunction

function! s:fzf(name, opts, extra)
  call s:check_requirements()

  let [extra, bang] = [{}, 0]
  if len(a:extra) <= 1
    let first = get(a:extra, 0, 0)
    if type(first) == s:TYPE.dict
      let extra = first
    else
      let bang = first
    endif
  elseif len(a:extra) == 2
    let [extra, bang] = a:extra
  else
    throw 'invalid number of arguments'
  endif

  let extra  = copy(extra)
  let eopts  = has_key(extra, 'options') ? remove(extra, 'options') : ''
  let merged = extend(copy(a:opts), extra)
  call s:merge_opts(merged, eopts)
  return fzf#run(s:wrap(a:name, merged, bang))
endfunction

let s:default_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

function! s:action_for(key, ...)
  let default = a:0 ? a:1 : ''
  let Cmd = get(get(g:, 'fzf_action', s:default_action), a:key, default)
  return type(Cmd) == s:TYPE.string ? Cmd : default
endfunction

function! s:open(cmd, target)
  if stridx('edit', a:cmd) == 0 && fnamemodify(a:target, ':p') ==# expand('%:p')
    normal! m'
    return
  endif
  execute a:cmd s:escape(a:target)
endfunction

function! s:warn(message)
  echohl WarningMsg
  echom a:message
  echohl None
  return 0
endfunction

function! s:fill_quickfix(list, ...)
  if len(a:list) > 1
    call setqflist(a:list)
    copen
    wincmd p
    if a:0
      execute a:1
    endif
  endif
endfunction

" ------------------------------------------------------------------
" Devicon Common
" ------------------------------------------------------------------

" The follow was copied from the `fzf` plugin. It is declared there (and here)
" with a script scope so we don't have direct access to it
function! s:fzf_expand(fmt)
  return s:fzf_call('expand', a:fmt, 1)
endfunction

function! s:devicon_common_sink(action, lines) abort
  if len(a:lines) < 2
    return
  endif
  let key = remove(a:lines, 0)
  let Cmd = get(a:action, key, 'e')

  " This is there devicon stripping happens
  " It is AFTER we grab the first item as the key as this allows
  " actions to work correctly
  let lines = map(a:lines, "join(split(v:val, ' ')[1:], ' ')")

  if type(Cmd) == type(function('call'))
    return Cmd(lines)
  endif
  if len(lines) > 1
    augroup fzf_swap
      autocmd SwapExists * let v:swapchoice='o'
            \| call s:warn('fzf: E325: swap file exists: '.s:fzf_expand('<afile>'))
    augroup END
  endif
  try
    let empty = empty(s:fzf_expand('%')) && line('$') == 1 && empty(getline(1)) && !&modified
    let autochdir = &autochdir
    set noautochdir
    for item in lines
      if empty
        execute 'e' s:escape(item)
        let empty = 0
      else
        call s:open(Cmd, item)
      endif
      if !has('patch-8.0.0177') && !has('nvim-0.2') && exists('#BufEnter')
            \ && isdirectory(item)
        doautocmd BufEnter
      endif
    endfor
  catch /^Vim:Interrupt$/
  finally
    let &autochdir = autochdir
    silent! autocmd! fzf_swap
  endtry
endfunction

" ------------------------------------------------------------------
" Files - Modified with Devicons
" ------------------------------------------------------------------
function! s:shortpath()
  let short = fnamemodify(getcwd(), ':~:.')
  if !has('win32unix')
    let short = pathshorten(short)
  endif
  let slash = (s:is_win && !&shellslash) ? '\' : '/'
  return empty(short) ? '~'.slash : short . (short =~ escape(slash, '\').'$' ? '' : slash)
endfunction

function! fzf#devicon#vim#files(dir, ...)
  if !executable('devicon-lookup')
    return s:warn('devicon-lookup is not found. It can be installed with `cargo install devicon-lookup`')
  endif

  let args = {}
  if !empty(a:dir)
    if !isdirectory(expand(a:dir))
      return s:warn('Invalid directory')
    endif
    let slash = (s:is_win && !&shellslash) ? '\\' : '/'
    let dir = substitute(a:dir, '[/\\]*$', slash, '')
    let args.dir = dir
  else
    let dir = s:shortpath()
  endif

  let args.options = ['-m', '--prompt', strwidth(dir) < &columns / 2 - 20 ? dir : '> ']
  let args.source = $FZF_DEFAULT_COMMAND.' | devicon-lookup'

  call s:merge_opts(args, get(g:, 'fzf_files_options', []))
  function! args.sink(lines) abort
    return s:devicon_common_sink(self._action, a:lines)
  endfunction
  let args['sink*'] = remove(args, 'sink')

  return s:fzf('files', args, a:000)
endfunction

" ------------------------------------------------------------------
" Lines
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" BLines
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" Colors
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" Locate - Modified with Devicons
" ------------------------------------------------------------------
function! fzf#devicon#vim#locate(query, ...)
  if !executable('devicon-lookup')
    return s:warn('devicon-lookup is not found. It can be installed with `cargo install devicon-lookup`')
  endif

  let args = {}

  let args.source = 'locate '.a:query.' | devicon-lookup'
  let args.options = '-m --prompt "Locate> "'

  function! args.sink(lines) abort
    return s:devicon_common_sink(self._action, a:lines)
  endfunction
  let args['sink*'] = remove(args, 'sink')

  return s:fzf('locate', args, a:000)
endfunction

" ------------------------------------------------------------------
" History[:/]
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" GFiles[?] - Modified with Devicons
" ------------------------------------------------------------------

function! s:get_git_root(dir)
  let dir = len(a:dir) ? a:dir : substitute(split(expand('%:p:h'), '[/\\]\.git\([/\\]\|$\)')[0], '^fugitive://', '', '')
  let root = systemlist('git -C ' . fzf#shellescape(dir) . ' rev-parse --show-toplevel')[0]
  return v:shell_error ? '' : (len(a:dir) ? fnamemodify(a:dir, ':p') : root)
endfunction

function! s:version_requirement(val, min)
  for idx in range(0, len(a:min) - 1)
    let v = get(a:val, idx, 0)
    if     v < a:min[idx] | return 0
    elseif v > a:min[idx] | return 1
    endif
  endfor
  return 1
endfunction

function! s:git_version_requirement(...)
  if !exists('s:git_version')
    let s:git_version = map(split(split(system('git --version'))[2], '\.'), 'str2nr(v:val)')
  endif
  return s:version_requirement(s:git_version, a:000)
endfunction

function! fzf#devicon#vim#gitfiles(args, ...)
  if !executable('devicon-lookup')
    return s:warn('devicon-lookup is not found. It can be installed with `cargo install devicon-lookup`')
  endif

  let dir = get(get(a:, 1, {}), 'dir', '')
  let root = s:get_git_root(dir)
  if empty(root)
    return s:warn('Not in git repo')
  endif
  let prefix = 'git -C ' . fzf#shellescape(root) . ' '
  if a:args !=# '?'
    let args = {}

    let args.source = prefix . 'ls-files ' . a:args
    if s:git_version_requirement(2, 31)
      let args.source .= ' --deduplicate'
    endif
    let args.source .= ' | devicon-lookup'
    let args.dir = root
    let args.options = '-m --prompt "GitFiles> "'

    function! args.sink(lines) abort
      return s:devicon_common_sink(self._action, a:lines)
    endfunction
    let args['sink*'] = remove(args, 'sink')

    return s:fzf('gfiles', args, a:000)
  endif

  " Here be dragons!
  " We're trying to access the common sink function that fzf#wrap injects to
  " the options dictionary.
  let bar = s:is_win ? '^|' : '|'
  let diff_prefix = 'git -C ' . s:escape_for_bash(root) . ' '
  let preview = printf(
    \ s:bash() . ' -c "if [[ {2} =~ M ]]; then %s; else %s {-1}; fi"',
    \ executable('delta')
      \ ? diff_prefix . 'diff -- {-1} ' . bar . ' delta --width $FZF_PREVIEW_COLUMNS --file-style=omit ' . bar . ' sed 1d'
      \ : diff_prefix . 'diff --color=always -- {-1} ' . bar . ' sed 1,4d',
    \ s:escape_for_bash(s:bin.preview))
  let wrapped = fzf#wrap({
  \ 'source':  prefix . '-c color.status=always status --short --untracked-files=all | devicon-lookup',
  \ 'dir':     root,
  \ 'options': ['--ansi', '--multi', '--nth', '2..,..', '--tiebreak=index', '--prompt', 'GitFiles?> ', '--preview', preview]
  \})
  call s:remove_layout(wrapped)
  let wrapped.common_sink = remove(wrapped, 'sink*')
  function! wrapped.newsink(lines)
    let lines = extend(a:lines[0:0], map(a:lines[1:], 'substitute(v:val[3:], ".* -> ", "", "")'))
    return s:devicon_common_sink(self._action, lines)
  endfunction
  let wrapped['sink*'] = remove(wrapped, 'newsink')
  return s:fzf('gfiles-diff', wrapped, a:000)
endfunction

" ------------------------------------------------------------------
" Buffers
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" Ag / Rg - TODO: Required devicon-lookup changes to support regex for
" filename
"
" These are correctly prefixed just don't do anything new yet
" ------------------------------------------------------------------
function! s:ag_to_qf(line)
  let parts = matchlist(a:line, '\(.\{-}\)\s*:\s*\(\d\+\)\%(\s*:\s*\(\d\+\)\)\?\%(\s*:\(.*\)\)\?')
  let dict = {'filename': &autochdir ? fnamemodify(parts[1], ':p') : parts[1], 'lnum': parts[2], 'text': parts[4]}
  if len(parts[3])
    let dict.col = parts[3]
  endif
  return dict
endfunction

function! s:ag_handler(lines)
  if len(a:lines) < 2
    return
  endif

  let cmd = s:action_for(a:lines[0], 'e')
  let list = map(filter(a:lines[1:], 'len(v:val)'), 's:ag_to_qf(v:val)')
  if empty(list)
    return
  endif

  let first = list[0]
  try
    call s:open(cmd, first.filename)
    execute first.lnum
    if has_key(first, 'col')
      call cursor(0, first.col)
    endif
    normal! zvzz
  catch
  endtry

  call s:fill_quickfix(list)
endfunction

function! s:devicon_grep_sink(items)
  let items = map(a:items, "join(split(v:val, ' ')[1:], ' ')")

  call s:ag_handler(items)
endfunction

" query, [[ag options], options]
function! fzf#devicon#vim#ag(query, ...)
  if type(a:query) != s:TYPE.string
    return s:warn('Invalid query argument')
  endif
  let query = empty(a:query) ? '^(?=.)' : a:query
  let args = copy(a:000)
  let ag_opts = len(args) > 1 && type(args[0]) == s:TYPE.string ? remove(args, 0) : ''
  let command = ag_opts . ' -- ' . fzf#shellescape(query)
  return call('fzf#devicon#vim#ag_raw', insert(args, command, 0))
endfunction

" ag command suffix, [spec (dict)], [fullscreen (bool)]
function! fzf#devicon#vim#ag_raw(command_suffix, ...)
  if !executable('ag')
    return s:warn('ag is not found')
  endif
  return call('fzf#devicon#vim#grep', extend(['ag --nogroup --column --color '.a:command_suffix, 1], a:000))
endfunction

" command (string), [spec (dict)], [fullscreen (bool)]
function! fzf#devicon#vim#grep(grep_command, ...)
  if !executable('devicon-lookup')
    return s:warn('devicon-lookup is not found. It can be installed with `cargo install devicon-lookup`')
  endif

  let args = copy(a:000)
  let words = []
  for word in split(a:grep_command)
    if word !~# '^[a-z]'
      break
    endif
    call add(words, word)
  endfor
  let words   = empty(words) ? ['grep'] : words
  let name    = join(words, '-')
  let capname = join(map(words, 'toupper(v:val[0]).v:val[1:]'), '')
  let opts = {
  \ 'source':  a:grep_command.' | devicon-lookup --color --prefix :',
  \ 'options': ['--ansi', '--prompt', capname.'> ',
  \             '--multi', '--bind', 'alt-a:select-all,alt-d:deselect-all',
  \             '--delimiter', ':', '--preview-window', '+{2}-/2']
  \}
  if len(args) && type(args[0]) == s:TYPE.bool
    call remove(args, 0)
  endif

  function! opts.sink(lines)
    return s:devicon_grep_sink(a:lines)
  endfunction
  let opts['sink*'] = remove(opts, 'sink')
  try
    let prev_default_command = $FZF_DEFAULT_COMMAND
    let $FZF_DEFAULT_COMMAND = a:grep_command
    return s:fzf(name, opts, args)
  finally
    let $FZF_DEFAULT_COMMAND = prev_default_command
  endtry
endfunction


" command_prefix (string), initial_query (string), [spec (dict)], [fullscreen (bool)]
function! fzf#devicon#vim#grep2(command_prefix, query, ...)
  let args = copy(a:000)
  let words = []
  for word in split(a:command_prefix)
    if word !~# '^[a-z]'
      break
    endif
    call add(words, word)
  endfor
  let words = empty(words) ? ['grep'] : words
  let name = join(words, '-')
  let opts = {
  \ 'source': ':',
  \ 'options': ['--ansi', '--prompt', toupper(name).'> ', '--query', a:query,
  \             '--disabled',
  \             '--bind', 'start:reload:'.a:command_prefix.' '.shellescape(a:query) . '| devicon-lookup --color --prefix :',
  \             '--bind', 'change:reload:'.a:command_prefix.' {q} | devicon-lookup --color --prefix : || :',
  \             '--multi', '--bind', 'alt-a:select-all,alt-d:deselect-all',
  \             '--delimiter', ':', '--preview-window', '+{2}-/2']
  \}
  if len(args) && type(args[0]) == s:TYPE.bool
    call remove(args, 0)
  endif
  function! opts.sink(lines)
    return s:devicon_grep_sink(a:lines)
  endfunction
  let opts['sink*'] = remove(opts, 'sink')
  return s:fzf(name, opts, args)
endfunction

" ------------------------------------------------------------------
" BTags
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" Snippets (UltiSnips)
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" Commands
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" Marks
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" Help tags
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" File types
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" Windows
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" Commits / BCommits
" ------------------------------------------------------------------

" ------------------------------------------------------------------
" fzf#vim#maps(mode, opts[with count and op])
" ------------------------------------------------------------------

" ----------------------------------------------------------------------------
" fzf#vim#complete - completion helper
" ----------------------------------------------------------------------------

" ------------------------------------------------------------------
let &cpoptions = s:cpo_save
unlet s:cpo_save
