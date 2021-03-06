" Ctags module for Gutentags

" Global Options {{{

if !exists('g:gutentags_ctags_executable')
    let g:gutentags_ctags_executable = 'ctags'
endif

if !exists('g:gutentags_tagfile')
    let g:gutentags_tagfile = 'tags'
endif

if !exists('g:gutentags_auto_set_tags')
    let g:gutentags_auto_set_tags = 1
endif

if !exists('g:gutentags_ctags_options_file')
    let g:gutentags_ctags_options_file = '.gutctags'
endif

" }}}

" Gutentags Module Interface {{{

let s:runner_exe = gutentags#get_plat_file('update_tags')

function! gutentags#ctags#init(project_root) abort
    " Figure out the path to the tags file.
    let b:gutentags_files['ctags'] = gutentags#get_cachefile(
                \a:project_root, g:gutentags_tagfile)

    " Set the tags file for Vim to use.
    if g:gutentags_auto_set_tags
        execute 'setlocal tags^=' . fnameescape(b:gutentags_files['ctags'])
    endif
endfunction

function! gutentags#ctags#generate(proj_dir, tags_file, write_mode) abort
    " Get to the tags file directory because ctags is finicky about
    " these things.
    let l:prev_cwd = getcwd()
    let l:work_dir = fnamemodify(a:tags_file, ':h')
    execute "chdir " . fnameescape(l:work_dir)

    try
        " Build the command line.
        let l:cmd = gutentags#get_execute_cmd() . s:runner_exe
        let l:cmd .= ' -e "' . s:get_ctags_executable() . '"'
        let l:cmd .= ' -t "' . a:tags_file . '"'
        let l:cmd .= ' -p "' . a:proj_dir . '"'
        if a:write_mode == 0 && filereadable(a:tags_file)
            let l:full_path = expand('%:p')
            let l:cmd .= ' -s "' . l:full_path . '"'
        endif
        for ign in split(&wildignore, ',')
            let l:cmd .= ' -x ' . '"' . ign . '"'
        endfor
        for exc in g:gutentags_exclude
            let l:cmd .= ' -x ' . '"' . exc . '"'
        endfor
        if g:gutentags_pause_after_update
            let l:cmd .= ' -c'
        endif
        let l:proj_options_file = a:proj_dir . '/' . 
                    \g:gutentags_ctags_options_file
        if filereadable(l:proj_options_file)
            let l:proj_options_file = s:process_options_file(
                        \a:proj_dir, l:proj_options_file)
            let l:cmd .= ' -o "' . l:proj_options_file . '"'
        endif
        if g:gutentags_trace
            if has('win32')
                let l:cmd .= ' -l "' . a:tags_file . '.log"'
            else
                let l:cmd .= ' > "' . a:tags_file . '.log" 2>&1'
            endif
        else
            if !has('win32')
                let l:cmd .= ' > /dev/null 2>&1'
            endif
        endif
        let l:cmd .= gutentags#get_execute_cmd_suffix()

        call gutentags#trace("Running: " . l:cmd)
        call gutentags#trace("In:      " . getcwd())
        if !g:gutentags_fake
            " Run the background process.
            if !g:gutentags_trace
                silent execute l:cmd
            else
                execute l:cmd
            endif

            " Flag this tags file as being in progress
            let l:full_tags_file = fnamemodify(a:tags_file, ':p')
            call gutentags#add_progress('ctags', l:full_tags_file)
        else
            call gutentags#trace("(fake... not actually running)")
        endif
        call gutentags#trace("")
    finally
        " Restore the previous working directory.
        execute "chdir " . fnameescape(l:prev_cwd)
    endtry
endfunction

" }}}

" Utilities {{{

" Get final ctags executable depending whether a filetype one is defined
function! s:get_ctags_executable() abort
    "Only consider the main filetype in cases like 'python.django'
    let l:ftype = get(split(&filetype, '\.'), 0, '')
    if exists('g:gutentags_ctags_executable_{l:ftype}')
        return g:gutentags_ctags_executable_{l:ftype}
    else
        return g:gutentags_ctags_executable
    endif
endfunction

function! s:process_options_file(proj_dir, path) abort
    if g:gutentags_cache_dir == ""
        " If we're not using a cache directory to store tag files, we can
        " use the options file straight away.
        return a:path
    endif

    " See if we need to process the options file.
    let l:do_process = 0
    let l:proj_dir = gutentags#stripslash(a:proj_dir)
    let l:out_path = gutentags#get_cachefile(l:proj_dir, 'options')
    if !filereadable(l:out_path)
        call gutentags#trace("Processing options file '".a:path."' because ".
                    \"it hasn't been processed yet.")
        let l:do_process = 1
    elseif getftime(a:path) > getftime(l:out_path)
        call gutentags#trace("Processing options file '".a:path."' because ".
                    \"it has changed.")
        let l:do_process = 1
    endif
    if l:do_process == 0
        " Nothing's changed, return the existing processed version of the
        " options file.
        return l:out_path
    endif

    " We have to process the options file. Right now this only means capturing
    " all the 'exclude' rules, and rewrite them to make them absolute.
    "
    " This is because since `ctags` is run with absolute paths (because we
    " want the tag file to be in a cache directory), it will do its path
    " matching with absolute paths too, so the exclude rules need to be
    " absolute.
    let l:lines = readfile(a:path)
    let l:outlines = []
    for line in l:lines
        let l:exarg = matchend(line, '\v^\-\-exclude=')
        if l:exarg < 0
            call add(l:outlines, line)
            continue
        endif
        let l:fullp = gutentags#normalizepath(l:proj_dir.'/'.
                    \strpart(line, l:exarg + 1))
        let l:ol = '--exclude='.l:fullp
        call add(l:outlines, l:ol)
    endfor

    call writefile(l:outlines, l:out_path)
    return l:out_path
endfunction

" }}}

