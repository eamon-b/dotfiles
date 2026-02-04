" ~/.vimrc - Vim configuration

" ==============================================================================
" General Settings
" ==============================================================================

set nocompatible              " Use Vim settings, not Vi
filetype plugin indent on     " Enable filetype detection, plugins, and indentation
syntax on                     " Enable syntax highlighting

set encoding=utf-8            " Use UTF-8 encoding
set fileencoding=utf-8        " Save files as UTF-8

set hidden                    " Allow switching buffers without saving
set autoread                  " Auto-reload files changed outside vim
set nobackup                  " Don't create backup files
set nowritebackup             " Don't create backup files during write
set noswapfile                " Don't create swap files

set history=1000              " Remember more commands
set undolevels=1000           " More undo levels

" ==============================================================================
" User Interface
" ==============================================================================

set number                    " Show line numbers
set relativenumber            " Show relative line numbers
set cursorline                " Highlight current line
set showcmd                   " Show command in bottom bar
set showmode                  " Show current mode
set ruler                     " Show cursor position
set laststatus=2              " Always show status line

set wildmenu                  " Visual autocomplete for command menu
set wildmode=longest:full,full
set wildignore+=*.o,*.obj,*.pyc,*.pyo,*/__pycache__/*
set wildignore+=*.swp,*~,*.bak
set wildignore+=node_modules/*,venv/*,.git/*

set scrolloff=5               " Keep 5 lines above/below cursor
set sidescrolloff=5           " Keep 5 columns left/right of cursor

set splitbelow                " Open horizontal splits below
set splitright                " Open vertical splits to the right

set termguicolors             " Enable true colors (if terminal supports it)
set background=dark           " Use dark background

" ==============================================================================
" Indentation
" ==============================================================================

set tabstop=4                 " Tab width
set shiftwidth=4              " Indent width
set softtabstop=4             " Backspace through expanded tabs
set expandtab                 " Use spaces instead of tabs
set autoindent                " Copy indent from current line
set smartindent               " Smart autoindenting on new lines
set shiftround                " Round indent to multiple of shiftwidth

" ==============================================================================
" Search
" ==============================================================================

set incsearch                 " Search as you type
set hlsearch                  " Highlight search results
set ignorecase                " Case-insensitive search
set smartcase                 " Case-sensitive if uppercase present

" ==============================================================================
" Text Handling
" ==============================================================================

set backspace=indent,eol,start  " Allow backspace over everything
set wrap                        " Wrap long lines
set linebreak                   " Wrap at word boundaries
set textwidth=0                 " Don't auto-wrap text
set formatoptions-=t            " Don't auto-wrap text while typing

set list                        " Show invisible characters
set listchars=tab:»·,trail:·,nbsp:·  " Display tabs and trailing spaces

" ==============================================================================
" Mouse and Clipboard
" ==============================================================================

set mouse=a                   " Enable mouse in all modes
set clipboard=unnamedplus     " Use system clipboard

" ==============================================================================
" Performance
" ==============================================================================

set lazyredraw                " Don't redraw during macros
set ttyfast                   " Faster terminal connection
set updatetime=300            " Faster completion

" ==============================================================================
" Key Mappings
" ==============================================================================

" Set leader key to space
let mapleader = " "

" Quick save and quit
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>x :x<CR>

" Clear search highlighting
nnoremap <leader><space> :nohlsearch<CR>

" Better window navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Resize windows with arrow keys
nnoremap <C-Up> :resize +2<CR>
nnoremap <C-Down> :resize -2<CR>
nnoremap <C-Left> :vertical resize -2<CR>
nnoremap <C-Right> :vertical resize +2<CR>

" Move lines up/down
nnoremap <A-j> :m .+1<CR>==
nnoremap <A-k> :m .-2<CR>==
vnoremap <A-j> :m '>+1<CR>gv=gv
vnoremap <A-k> :m '<-2<CR>gv=gv

" Stay in visual mode when indenting
vnoremap < <gv
vnoremap > >gv

" Quick buffer navigation
nnoremap <leader>bn :bnext<CR>
nnoremap <leader>bp :bprevious<CR>
nnoremap <leader>bd :bdelete<CR>

" Quick split
nnoremap <leader>v :vsplit<CR>
nnoremap <leader>h :split<CR>

" Open file explorer
nnoremap <leader>e :Explore<CR>

" Quick access to vimrc
nnoremap <leader>ev :edit $MYVIMRC<CR>
nnoremap <leader>sv :source $MYVIMRC<CR>

" Y yanks to end of line (consistent with D and C)
nnoremap Y y$

" Keep cursor centered when jumping
nnoremap n nzzzv
nnoremap N Nzzzv
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz

" ==============================================================================
" Filetype-specific Settings
" ==============================================================================

augroup FileTypeSettings
    autocmd!

    " JavaScript/TypeScript/JSON/CSS/HTML - 2 space indent
    autocmd FileType javascript,javascriptreact,typescript,typescriptreact setlocal ts=2 sw=2 sts=2
    autocmd FileType json,css,scss,html,vue,svelte setlocal ts=2 sw=2 sts=2
    autocmd FileType yaml setlocal ts=2 sw=2 sts=2

    " Python
    autocmd FileType python setlocal ts=4 sw=4 sts=4 textwidth=88

    " C/C++
    autocmd FileType c,cpp setlocal ts=4 sw=4 sts=4

    " Go uses tabs
    autocmd FileType go setlocal noexpandtab ts=4 sw=4 sts=4

    " Makefiles use tabs
    autocmd FileType make setlocal noexpandtab ts=4 sw=4 sts=4

    " Git commits
    autocmd FileType gitcommit setlocal textwidth=72 spell

    " Markdown
    autocmd FileType markdown setlocal wrap spell
augroup END

" ==============================================================================
" Auto Commands
" ==============================================================================

augroup GeneralSettings
    autocmd!

    " Remove trailing whitespace on save (except markdown)
    autocmd BufWritePre * if &filetype != 'markdown' | %s/\s\+$//e | endif

    " Return to last edit position when opening files
    autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif

    " Auto-resize splits when Vim is resized
    autocmd VimResized * wincmd =
augroup END

" ==============================================================================
" Status Line
" ==============================================================================

set statusline=
set statusline+=%#PmenuSel#
set statusline+=\ %f                          " File path
set statusline+=\ %m                          " Modified flag
set statusline+=%#LineNr#
set statusline+=%=                            " Right align
set statusline+=%#CursorColumn#
set statusline+=\ %y                          " File type
set statusline+=\ %{&fileencoding?&fileencoding:&encoding}
set statusline+=\ [%{&fileformat}]
set statusline+=\ %p%%                        " Percentage through file
set statusline+=\ %l:%c                       " Line:Column
set statusline+=\

" ==============================================================================
" netrw Settings (built-in file explorer)
" ==============================================================================

let g:netrw_banner = 0           " Hide banner
let g:netrw_liststyle = 3        " Tree view
let g:netrw_browse_split = 4     " Open in previous window
let g:netrw_altv = 1             " Open splits to the right
let g:netrw_winsize = 25         " Width of explorer
