" denops 版 skkeleton の Vim script API との互換レイヤー
" 実体は全て lua/skkeleton/ 以下にある

function! skkeleton#mode() abort
  return luaeval('require("skkeleton").mode()')
endfunction

function! skkeleton#is_enabled() abort
  return luaeval('require("skkeleton").is_enabled()')
endfunction

function! skkeleton#get_default_mapped_keys() abort
  return luaeval('require("skkeleton").get_default_mapped_keys()')
endfunction

function! skkeleton#map() abort
  call luaeval('require("skkeleton").map()')
endfunction

function! skkeleton#handle(func, opts) abort
  return luaeval('require("skkeleton").handle(_A[1], _A[2])', [a:func, a:opts])
endfunction

function! skkeleton#config(config) abort
  call luaeval('require("skkeleton").config(_A)', a:config)
endfunction

function! skkeleton#register_keymap(state, key, func_name) abort
  call luaeval('require("skkeleton").register_keymap(_A[1], _A[2], _A[3])',
        \ [a:state, a:key, a:func_name])
endfunction

function! skkeleton#register_kanatable(table_name, table, create=v:false) abort
  call luaeval('require("skkeleton").register_kanatable(_A[1], _A[2], _A[3])',
        \ [a:table_name, a:table, a:create])
endfunction

function! skkeleton#register_kanatable_file(table_name, path, encoding='', create=v:false) abort
  call luaeval('require("skkeleton").register_kanatable_file(_A[1], _A[2], _A[3], _A[4])',
        \ [a:table_name, a:path, a:encoding, a:create])
endfunction

function! skkeleton#initialize() abort
  call luaeval('require("skkeleton").initialize()')
endfunction

function! skkeleton#disable() abort
  call luaeval('require("skkeleton").disable_impl()')
endfunction

function! skkeleton#get_config() abort
  return luaeval('require("skkeleton").get_config()')
endfunction

function! skkeleton#vim_status() abort
  return luaeval('require("skkeleton").vim_status()')
endfunction

function! skkeleton#dangerously_clear_buffer_local_mappings() abort
  call luaeval('require("skkeleton").dangerously_clear_buffer_local_mappings()')
endfunction

function! skkeleton#update_database(path, ...) abort
  call luaeval('require("skkeleton").update_database()')
endfunction
